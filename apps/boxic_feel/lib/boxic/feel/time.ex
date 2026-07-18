defmodule Boxic.FEEL.Time do
  @moduledoc """
  Lossless FEEL time value.

  This type exists because neither Elixir's `Time` nor Erlang's `:calendar`
  represents the complete FEEL time domain. Elixir time is limited to
  microsecond precision and carries no zone identity. OTP's RFC 3339 helpers
  can convert conventional numeric offsets to an instant, but do not represent
  floating times, IANA zone names, or second-precision offsets as values.

  FEEL requires all of those distinctions. In particular, a floating time is
  not interchangeable with a zoned time, and an IANA zone name must be retained
  even when an offset can be resolved for comparison. Seconds are therefore
  stored as `Decimal` for up to nanosecond precision, while `zone` explicitly
  records floating, numeric-offset, or named-zone identity.

  Named-zone validation uses the IANA database through `tz`; the value
  representation remains independent of that resolver.
  """

  defstruct [:hour, :minute, :second, :zone]

  @type zone :: :floating | {:offset, integer()} | {:iana, String.t()}
  @type t :: %__MODULE__{
          hour: 0..23,
          minute: 0..59,
          second: Decimal.t(),
          zone: zone()
        }

  @time_pattern ~r/^(?<hour>\d{2}):(?<minute>\d{2}):(?<second>\d{2}(?:\.\d{1,9})?)(?<zone>Z|[+-]\d{2}:\d{2}(?::\d{2})?|@[A-Za-z_]+(?:\/[A-Za-z0-9_+.-]+)*)?$/

  @doc """
  Creates a validated FEEL time.

      Boxic.FEEL.Time.new(12, 30, Decimal.new("15.5"), {:offset, 0})
  """
  @spec new(integer(), integer(), Decimal.t() | integer(), zone()) :: {:ok, t()} | :error
  def new(hour, minute, second, zone \\ :floating) do
    second = decimal(second)

    if hour in 0..23 and minute in 0..59 and
         Decimal.compare(second, Decimal.new(0)) != :lt and
         Decimal.compare(second, Decimal.new(60)) == :lt and valid_zone?(zone) do
      {:ok, %__MODULE__{hour: hour, minute: minute, second: second, zone: zone}}
    else
      :error
    end
  end

  @doc """
  Parses a FEEL time, preserving fractional seconds and zone identity.

      Boxic.FEEL.Time.parse("12:30:15.5Z")
  """
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(value) when is_binary(value) do
    with captures when not is_nil(captures) <- Regex.named_captures(@time_pattern, value),
         {:ok, zone} <- parse_zone(captures["zone"]),
         {:ok, time} <-
           new(
             String.to_integer(captures["hour"]),
             String.to_integer(captures["minute"]),
             Decimal.new(captures["second"]),
             zone
           ) do
      {:ok, time}
    else
      _ -> :error
    end
  end

  @doc """
  Converts an Elixir time into a floating FEEL time.

      Boxic.FEEL.Time.from_elixir(~T[12:30:15])
  """
  @spec from_elixir(Time.t()) :: t()
  def from_elixir(%Elixir.Time{} = value) do
    {microsecond, precision} = value.microsecond

    fraction =
      if precision == 0 do
        Decimal.new(value.second)
      else
        Decimal.new(
          "#{value.second}.#{microsecond |> Integer.to_string() |> String.pad_leading(6, "0") |> binary_part(0, precision)}"
        )
      end

    %__MODULE__{hour: value.hour, minute: value.minute, second: fraction, zone: :floating}
  end

  @doc """
  Serializes a FEEL time.

      Boxic.FEEL.Time.to_string(time)
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = value) do
    two(value.hour) <>
      ":" <> two(value.minute) <> ":" <> format_second(value.second) <> format_zone(value.zone)
  end

  @doc """
  Returns seconds since local midnight without applying a zone offset.

      Boxic.FEEL.Time.local_seconds(time)
  """
  @spec local_seconds(t()) :: Decimal.t()
  def local_seconds(%__MODULE__{} = value) do
    value.second
    |> Decimal.add(Decimal.new(value.hour * 3_600 + value.minute * 60))
  end

  @doc """
  Compares compatible FEEL times, returning `:unordered` for incompatible zones.

      Boxic.FEEL.Time.compare(left, right)
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt | :unordered
  def compare(%__MODULE__{} = left, %__MODULE__{} = right) do
    case {comparison_seconds(left), comparison_seconds(right)} do
      {{:ok, left_seconds}, {:ok, right_seconds}} -> Decimal.compare(left_seconds, right_seconds)
      _ when left.zone == right.zone -> Decimal.compare(local_seconds(left), local_seconds(right))
      _ -> :unordered
    end
  end

  @doc """
  Calculates `left - right` when the time values are comparable.

      Boxic.FEEL.Time.difference(left, right)
  """
  @spec difference(t(), t()) :: {:ok, Boxic.FEEL.Duration.t()} | :error
  def difference(%__MODULE__{} = left, %__MODULE__{} = right) do
    case {comparison_seconds(left), comparison_seconds(right)} do
      {{:ok, left_seconds}, {:ok, right_seconds}} ->
        {:ok, Boxic.FEEL.Duration.from_seconds(Decimal.sub(left_seconds, right_seconds))}

      _ when left.zone == right.zone ->
        {:ok,
         Boxic.FEEL.Duration.from_seconds(Decimal.sub(local_seconds(left), local_seconds(right)))}

      _ ->
        :error
    end
  end

  @doc """
  Adds seconds and wraps the result within one day.

      Boxic.FEEL.Time.add_seconds(time, Decimal.new("0.5"))
  """
  @spec add_seconds(t(), integer() | Decimal.t()) :: t()
  def add_seconds(%__MODULE__{} = value, seconds) do
    day = Decimal.new(86_400)
    total = Decimal.add(local_seconds(value), decimal(seconds))
    normalized = Decimal.rem(total, day)

    normalized =
      if Decimal.negative?(normalized), do: Decimal.add(normalized, day), else: normalized

    integer_seconds = normalized |> Decimal.round(0, :down) |> Decimal.to_integer()
    fraction = Decimal.sub(normalized, Decimal.new(integer_seconds))

    %__MODULE__{
      hour: div(integer_seconds, 3_600),
      minute: div(rem(integer_seconds, 3_600), 60),
      second: Decimal.add(Decimal.new(rem(integer_seconds, 60)), fraction),
      zone: value.zone
    }
  end

  defp comparison_seconds(%__MODULE__{zone: {:offset, offset}} = value),
    do: {:ok, Decimal.sub(local_seconds(value), Decimal.new(offset))}

  defp comparison_seconds(_value), do: :error

  defp parse_zone(value) when value in [nil, ""], do: {:ok, :floating}
  defp parse_zone("Z"), do: {:ok, {:offset, 0}}

  defp parse_zone("@" <> name) do
    if iana_zone?(name), do: {:ok, {:iana, name}}, else: :error
  end

  defp parse_zone(<<sign, hour::binary-size(2), ?:, minute::binary-size(2), rest::binary>>)
       when sign in [?+, ?-] do
    with {hour, ""} <- Integer.parse(hour),
         {minute, ""} <- Integer.parse(minute),
         true <- hour <= 14 and minute < 60,
         {:ok, second} <- offset_second(rest) do
      multiplier = if sign == ?+, do: 1, else: -1
      {:ok, {:offset, multiplier * (hour * 3_600 + minute * 60 + second)}}
    else
      _ -> :error
    end
  end

  defp parse_zone(_value), do: :error

  defp offset_second(""), do: {:ok, 0}

  defp offset_second(<<?:, second::binary-size(2)>>) do
    case Integer.parse(second) do
      {value, ""} when value < 60 -> {:ok, value}
      _ -> :error
    end
  end

  defp offset_second(_value), do: :error

  defp valid_zone?(:floating), do: true
  defp valid_zone?({:offset, seconds}), do: is_integer(seconds) and abs(seconds) <= 14 * 3_600
  defp valid_zone?({:iana, name}), do: is_binary(name) and name != ""
  defp valid_zone?(_zone), do: false

  defp iana_zone?(name) do
    case Tz.TimeZoneDatabase.time_zone_periods_from_wall_datetime(
           ~N[2000-01-01 00:00:00],
           name
         ) do
      {:error, :time_zone_not_found} -> false
      _result -> true
    end
  end

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value), do: Decimal.new(value)

  defp format_second(value) do
    case String.split(Decimal.to_string(value, :normal), ".", parts: 2) do
      [integer] -> String.pad_leading(integer, 2, "0")
      [integer, fraction] -> String.pad_leading(integer, 2, "0") <> "." <> fraction
    end
  end

  defp format_zone(:floating), do: ""
  defp format_zone({:offset, 0}), do: "Z"

  defp format_zone({:offset, seconds}) do
    sign = if seconds < 0, do: "-", else: "+"
    seconds = abs(seconds)
    hour = div(seconds, 3_600)
    minute = div(rem(seconds, 3_600), 60)
    second = rem(seconds, 60)
    base = sign <> two(hour) <> ":" <> two(minute)
    if second == 0, do: base, else: base <> ":" <> two(second)
  end

  defp format_zone({:iana, name}), do: "@" <> name
  defp two(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")
end
