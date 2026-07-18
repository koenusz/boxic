defmodule Boxic.FEEL.DateTime do
  @moduledoc """
  Lossless FEEL date-time composed of an Elixir `Date` and a FEEL time.

  We retain Elixir's `Date` because its proleptic ISO calendar supports FEEL's
  signed year range through ±999,999,999. We do not use Elixir `DateTime` or
  `NaiveDateTime` for the complete value because they inherit microsecond time
  precision, and `DateTime` depends on a timezone database while normalizing
  values around an instant.

  FEEL also needs the original temporal form: floating versus offset-based
  versus IANA-zoned values can affect equality, ordering, properties, and
  serialization. Composing `Date` with `Boxic.FEEL.Time` preserves that
  information and allows instant normalization to remain an explicit semantic
  operation instead of losing source precision or zone identity at parse time.
  """

  alias Boxic.FEEL.Time, as: FeelTime
  alias Boxic.FEEL.Duration

  defstruct [:date, :time]

  @type t :: %__MODULE__{date: Date.t(), time: FeelTime.t()}

  @doc """
  Combines a date and FEEL time without discarding zone identity.

      Boxic.FEEL.DateTime.new(~D[2026-01-01], time)
  """
  @spec new(Date.t(), FeelTime.t()) :: t()
  def new(%Date{} = date, %FeelTime{} = time), do: %__MODULE__{date: date, time: time}

  @doc """
  Parses a FEEL date-time.

      Boxic.FEEL.DateTime.parse("2026-01-01T12:30:00Z")
  """
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(value) when is_binary(value) do
    case String.split(value, "T", parts: 2) do
      [date_part, time_part] ->
        with {:ok, date} <- parse_date(date_part),
             {:ok, date, time_part} <- normalize_end_of_day(date, time_part),
             {:ok, time} <- FeelTime.parse(time_part) do
          {:ok, new(date, time)}
        end

      _ ->
        :error
    end
  end

  defp normalize_end_of_day(date, "24:00:00" <> zone),
    do: {:ok, Date.add(date, 1), "00:00:00" <> zone}

  defp normalize_end_of_day(_date, "24:" <> _rest), do: :error
  defp normalize_end_of_day(date, time), do: {:ok, date, time}

  @doc """
  Serializes a FEEL date-time.

      Boxic.FEEL.DateTime.to_string(value)
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{date: date, time: time}) do
    Date.to_iso8601(date) <> "T" <> FeelTime.to_string(time)
  end

  @doc """
  Compares compatible FEEL date-times.

      Boxic.FEEL.DateTime.compare(left, right)
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt | :unordered
  def compare(%__MODULE__{} = left, %__MODULE__{} = right) do
    case {instant_seconds(left), instant_seconds(right)} do
      {{:ok, left_seconds}, {:ok, right_seconds}} -> Decimal.compare(left_seconds, right_seconds)
      _ when left.time.zone == right.time.zone -> compare_local(left, right)
      _ -> :unordered
    end
  end

  @doc """
  Adds a year-month or day-time duration.

      Boxic.FEEL.DateTime.add_duration(value, duration)
  """
  @spec add_duration(t(), Duration.t()) :: {:ok, t()} | :error
  def add_duration(%__MODULE__{} = value, %Duration{kind: :year_month} = duration) do
    {:ok, %{value | date: Duration.add_to_date(value.date, duration)}}
  end

  def add_duration(
        %__MODULE__{date: %{year: year}, time: %FeelTime{zone: {:iana, zone}}} = value,
        %Duration{
          kind: :day_time,
          seconds: seconds
        }
      )
      when year > 0 do
    with {:ok, datetime} <- to_elixir_datetime(value, zone),
         {whole_seconds, fraction} <- split_seconds(seconds),
         shifted <-
           DateTime.add(datetime, whole_seconds, :second, Tzdata.TimeZoneDatabase),
         {:ok, result} <- from_elixir_datetime(shifted, fraction) do
      {:ok, result}
    else
      _ -> :error
    end
  end

  def add_duration(%__MODULE__{} = value, %Duration{kind: :day_time, seconds: seconds}) do
    total = Decimal.add(FeelTime.local_seconds(value.time), decimal(seconds))
    day = Decimal.new(86_400)
    day_delta = total |> Decimal.div(day) |> Decimal.round(0, :floor) |> Decimal.to_integer()

    {:ok,
     %{
       value
       | date: Date.add(value.date, day_delta),
         time: FeelTime.add_seconds(value.time, seconds)
     }}
  end

  @doc """
  Calculates `left - right` when both values share a comparable timeline.

      Boxic.FEEL.DateTime.difference(left, right)
  """
  @spec difference(t(), t()) :: {:ok, Duration.t()} | :error
  def difference(%__MODULE__{} = left, %__MODULE__{} = right) do
    with {:ok, left_seconds} <- instant_seconds(left),
         {:ok, right_seconds} <- instant_seconds(right) do
      {:ok, Duration.from_seconds(Decimal.sub(left_seconds, right_seconds))}
    else
      _ when left.time.zone == right.time.zone ->
        {:ok, Duration.from_seconds(Decimal.sub(local_seconds(left), local_seconds(right)))}

      _ ->
        :error
    end
  end

  defp local_seconds(%__MODULE__{date: date, time: time}) do
    date
    |> Date.to_gregorian_days()
    |> Kernel.*(86_400)
    |> Decimal.new()
    |> Decimal.add(FeelTime.local_seconds(time))
  end

  @doc """
  Converts a zoned FEEL date-time to seconds on a common timeline.

      Boxic.FEEL.DateTime.instant_seconds(value)
  """
  @spec instant_seconds(t()) :: {:ok, Decimal.t()} | :error
  def instant_seconds(%__MODULE__{date: date, time: %FeelTime{zone: {:offset, offset}} = time}) do
    seconds =
      date
      |> Date.to_gregorian_days()
      |> Kernel.*(86_400)
      |> Decimal.new()
      |> Decimal.add(FeelTime.local_seconds(time))
      |> Decimal.sub(Decimal.new(offset))

    {:ok, seconds}
  end

  def instant_seconds(%__MODULE__{date: date, time: %FeelTime{zone: {:iana, zone}} = time}) do
    case zone_offset(zone, date, time) do
      {:ok, offset} ->
        instant_seconds(%__MODULE__{date: date, time: %{time | zone: {:offset, offset}}})

      :error ->
        :error
    end
  end

  def instant_seconds(_value), do: :error

  defp compare_local(left, right) do
    case Date.compare(left.date, right.date) do
      :eq -> FeelTime.compare(left.time, right.time)
      result -> result
    end
  end

  defp zone_offset(zone, date, time) do
    second = time.second |> Decimal.round(0, :down) |> Decimal.to_integer()

    with {:ok, elixir_time} <- Elixir.Time.new(time.hour, time.minute, second),
         {:ok, datetime} <- DateTime.new(date, elixir_time, zone, Tzdata.TimeZoneDatabase) do
      {:ok, datetime.utc_offset + datetime.std_offset}
    else
      _ -> :error
    end
  end

  defp to_elixir_datetime(%__MODULE__{date: date, time: time}, zone) do
    second = time.second |> Decimal.round(0, :down) |> Decimal.to_integer()

    with {:ok, elixir_time} <- Elixir.Time.new(time.hour, time.minute, second) do
      case DateTime.new(date, elixir_time, zone, Tzdata.TimeZoneDatabase) do
        {:ok, datetime} -> {:ok, datetime}
        {:ambiguous, first, _second} -> {:ok, first}
        _ -> :error
      end
    end
  end

  defp from_elixir_datetime(%DateTime{} = value, fraction) do
    second = Decimal.add(Decimal.new(value.second), fraction)

    with {:ok, time} <-
           FeelTime.new(value.hour, value.minute, second, {:iana, value.time_zone}) do
      {:ok, new(DateTime.to_date(value), time)}
    end
  end

  defp split_seconds(seconds) do
    seconds = decimal(seconds)
    whole = seconds |> Decimal.round(0, :down) |> Decimal.to_integer()
    {whole, Decimal.sub(seconds, Decimal.new(whole))}
  end

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value), do: Decimal.new(value)

  defp parse_date(value) do
    case Regex.run(~r/^(-?(?:\d{4}|[1-9]\d{4,8}))-(\d{2})-(\d{2})$/, value,
           capture: :all_but_first
         ) do
      [year, month, day] ->
        Date.new(String.to_integer(year), String.to_integer(month), String.to_integer(day))

      _ ->
        :error
    end
  end
end
