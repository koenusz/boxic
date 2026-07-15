defmodule Arbiter.FEEL.Duration do
  @moduledoc """
  FEEL duration value.

  FEEL defines year-month and day-time durations as distinct, generally
  incomparable kinds. A single elapsed-seconds value cannot represent calendar
  months, while Elixir's date/time APIs do not provide a value that preserves
  this FEEL distinction or fractional duration seconds.

  The explicit `kind` field prevents accidental comparison or property access
  across the two domains. Year-month values use `months`; day-time values use
  `seconds`, with `Decimal` retained when fractional precision is present.
  """

  defstruct [:kind, :months, :seconds]

  @type kind :: :year_month | :day_time
  @type t :: %__MODULE__{kind: kind(), months: integer(), seconds: integer() | Decimal.t()}

  @spec parse_iso8601(String.t()) :: {:ok, t()} | {:error, :invalid_duration}
  def parse_iso8601(value) when is_binary(value) do
    regex =
      ~r/^(?<sign>-)?P(?:(?<years>\d+)Y)?(?:(?<months>\d+)M)?(?:(?<days>\d+)D)?(?:T(?:(?<hours>\d+)H)?(?:(?<minutes>\d+)M)?(?:(?<seconds>\d+(?:\.\d*)?)S)?)?$/

    case Regex.named_captures(regex, value) do
      nil ->
        {:error, :invalid_duration}

      captures ->
        if Enum.all?(~w(years months days hours minutes seconds), &(captures[&1] in [nil, ""])) do
          {:error, :invalid_duration}
        else
          years = int(captures["years"])
          months = int(captures["months"])
          days = int(captures["days"])
          hours = int(captures["hours"])
          minutes = int(captures["minutes"])
          seconds = number(captures["seconds"])

          sign = if captures["sign"] == "-", do: -1, else: 1
          kind = if years != 0 or months != 0, do: :year_month, else: :day_time

          {:ok,
           %__MODULE__{
             kind: kind,
             months: sign * (years * 12 + months),
             seconds:
               multiply(sign, add_number(days * 86_400 + hours * 3_600 + minutes * 60, seconds))
           }}
        end
    end
  end

  @spec from_days(integer()) :: t()
  def from_days(days), do: %__MODULE__{kind: :day_time, months: 0, seconds: days * 86_400}

  @spec from_seconds(integer()) :: t()
  def from_seconds(seconds), do: %__MODULE__{kind: :day_time, months: 0, seconds: seconds}

  @spec negate(t()) :: t()
  def negate(%__MODULE__{kind: kind, months: months, seconds: seconds}) do
    %__MODULE__{kind: kind, months: -months, seconds: multiply(-1, seconds)}
  end

  @spec abs(t()) :: t()
  def abs(%__MODULE__{kind: kind, months: months, seconds: seconds}) do
    %__MODULE__{kind: kind, months: Kernel.abs(months), seconds: abs_number(seconds)}
  end

  @spec add(t(), t()) :: t()
  def add(%__MODULE__{} = left, %__MODULE__{} = right) do
    %__MODULE__{
      kind: if(left.kind == right.kind, do: left.kind, else: :day_time),
      months: left.months + right.months,
      seconds: add_number(left.seconds, right.seconds)
    }
  end

  @spec subtract(t(), t()) :: t()
  def subtract(%__MODULE__{} = left, %__MODULE__{} = right), do: add(left, negate(right))

  @spec compare(t(), t()) :: :lt | :eq | :gt | :unordered
  def compare(%__MODULE__{kind: kind} = left, %__MODULE__{kind: kind} = right) do
    case kind do
      :year_month -> compare_numbers(left.months, right.months)
      :day_time -> compare_numbers(left.seconds, right.seconds)
    end
  end

  def compare(%__MODULE__{}, %__MODULE__{}), do: :unordered

  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{kind: :year_month, months: months}) do
    sign = if months < 0, do: "-", else: ""
    months = Kernel.abs(months)
    years = div(months, 12)
    remainder = rem(months, 12)

    body =
      cond do
        years > 0 and remainder > 0 -> "#{years}Y#{remainder}M"
        years > 0 -> "#{years}Y"
        true -> "#{remainder}M"
      end

    sign <> "P" <> body
  end

  def to_string(%__MODULE__{kind: :day_time, seconds: seconds}) do
    seconds = decimal(seconds)
    sign = if Decimal.negative?(seconds), do: "-", else: ""
    seconds = Decimal.abs(seconds)
    whole = seconds |> Decimal.round(0, :down) |> Decimal.to_integer()
    fraction = Decimal.sub(seconds, Decimal.new(whole))
    days = div(whole, 86_400)
    hours = div(rem(whole, 86_400), 3_600)
    minutes = div(rem(whole, 3_600), 60)
    second = Decimal.add(Decimal.new(rem(whole, 60)), fraction)
    date_part = if days > 0, do: "#{days}D", else: ""

    time_part =
      [if(hours > 0, do: "#{hours}H"), if(minutes > 0, do: "#{minutes}M"), format_seconds(second)]
      |> Enum.reject(&is_nil/1)
      |> Enum.join()

    sign <> "P" <> date_part <> "T" <> time_part
  end

  @spec add_to_date(Date.t(), t()) :: Date.t()
  def add_to_date(%Date{} = date, %__MODULE__{} = duration) do
    date
    |> add_months(duration.months)
    |> Date.add(div(truncate(duration.seconds), 86_400))
  end

  @spec add_to_datetime(DateTime.t(), t()) :: DateTime.t()
  def add_to_datetime(%DateTime{} = datetime, %__MODULE__{} = duration) do
    shifted_date = add_months(DateTime.to_date(datetime), duration.months)

    {:ok, shifted_datetime} =
      DateTime.new(shifted_date, DateTime.to_time(datetime), datetime.time_zone)

    DateTime.add(shifted_datetime, truncate(duration.seconds), :second)
  end

  @spec add_to_time(Time.t(), t()) :: Time.t()
  def add_to_time(%Time{} = time, %__MODULE__{} = duration) do
    total_seconds =
      rem(
        time.hour * 3_600 + time.minute * 60 + time.second + truncate(duration.seconds),
        86_400
      )

    normalized = if total_seconds < 0, do: total_seconds + 86_400, else: total_seconds

    hour = div(normalized, 3_600)
    minute = div(rem(normalized, 3_600), 60)
    second = rem(normalized, 60)

    {:ok, result} = Time.new(hour, minute, second)
    result
  end

  defp add_months(%Date{} = date, 0), do: date

  defp add_months(%Date{} = date, months_delta) do
    total_month = date.month + months_delta
    year = date.year + floor_div(total_month - 1, 12)
    month = rem(total_month - 1, 12) + 1
    day = min(date.day, Date.days_in_month(%Date{year: year, month: month, day: 1}))

    {:ok, shifted} = Date.new(year, month, day)
    shifted
  end

  defp floor_div(value, divisor) do
    quotient = div(value, divisor)
    remainder = rem(value, divisor)

    if remainder < 0 do
      quotient - 1
    else
      quotient
    end
  end

  defp int(nil), do: 0
  defp int(""), do: 0
  defp int(value), do: String.to_integer(value)

  defp number(nil), do: 0
  defp number(""), do: 0

  defp number(value) do
    if String.contains?(value, "."),
      do: Decimal.new(String.trim_trailing(value, ".")),
      else: int(value)
  end

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value), do: Decimal.new(value)

  defp format_seconds(value) do
    if Decimal.equal?(value, Decimal.new(0)) do
      "0S"
    else
      Decimal.to_string(value, :normal) <> "S"
    end
  end

  defp add_number(%Decimal{} = left, right), do: Decimal.add(left, Decimal.new(right))
  defp add_number(left, %Decimal{} = right), do: Decimal.add(Decimal.new(left), right)
  defp add_number(left, right), do: left + right

  defp multiply(multiplier, %Decimal{} = value), do: Decimal.mult(Decimal.new(multiplier), value)
  defp multiply(multiplier, value), do: multiplier * value

  defp abs_number(%Decimal{} = value), do: Decimal.abs(value)
  defp abs_number(value), do: Kernel.abs(value)

  defp truncate(%Decimal{} = value), do: value |> Decimal.round(0, :down) |> Decimal.to_integer()
  defp truncate(value), do: value

  defp compare_numbers(%Decimal{} = left, %Decimal{} = right), do: Decimal.compare(left, right)
  defp compare_numbers(%Decimal{} = left, right), do: Decimal.compare(left, Decimal.new(right))
  defp compare_numbers(left, %Decimal{} = right), do: Decimal.compare(Decimal.new(left), right)
  defp compare_numbers(left, right) when left < right, do: :lt
  defp compare_numbers(left, right) when left > right, do: :gt
  defp compare_numbers(_left, _right), do: :eq
end
