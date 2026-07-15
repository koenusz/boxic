defmodule Arbiter.FEEL.Duration do
  @moduledoc """
  FEEL duration value.

  The representation tracks month-based and second-based components.
  """

  defstruct [:months, :seconds]

  @type t :: %__MODULE__{months: integer(), seconds: integer()}

  @spec parse_iso8601(String.t()) :: {:ok, t()} | {:error, :invalid_duration}
  def parse_iso8601(value) when is_binary(value) do
    regex =
      ~r/^P(?:(?<years>\d+)Y)?(?:(?<months>\d+)M)?(?:(?<days>\d+)D)?(?:T(?:(?<hours>\d+)H)?(?:(?<minutes>\d+)M)?(?:(?<seconds>\d+)S)?)?$/

    case Regex.named_captures(regex, value) do
      nil ->
        {:error, :invalid_duration}

      captures ->
        years = int(captures["years"])
        months = int(captures["months"])
        days = int(captures["days"])
        hours = int(captures["hours"])
        minutes = int(captures["minutes"])
        seconds = int(captures["seconds"])

        {:ok,
         %__MODULE__{
           months: years * 12 + months,
           seconds: days * 86_400 + hours * 3_600 + minutes * 60 + seconds
         }}
    end
  end

  @spec from_days(integer()) :: t()
  def from_days(days), do: %__MODULE__{months: 0, seconds: days * 86_400}

  @spec from_seconds(integer()) :: t()
  def from_seconds(seconds), do: %__MODULE__{months: 0, seconds: seconds}

  @spec negate(t()) :: t()
  def negate(%__MODULE__{months: months, seconds: seconds}) do
    %__MODULE__{months: -months, seconds: -seconds}
  end

  @spec add(t(), t()) :: t()
  def add(%__MODULE__{} = left, %__MODULE__{} = right) do
    %__MODULE__{months: left.months + right.months, seconds: left.seconds + right.seconds}
  end

  @spec subtract(t(), t()) :: t()
  def subtract(%__MODULE__{} = left, %__MODULE__{} = right), do: add(left, negate(right))

  @spec add_to_date(Date.t(), t()) :: Date.t()
  def add_to_date(%Date{} = date, %__MODULE__{} = duration) do
    date
    |> add_months(duration.months)
    |> Date.add(div(duration.seconds, 86_400))
  end

  @spec add_to_datetime(DateTime.t(), t()) :: DateTime.t()
  def add_to_datetime(%DateTime{} = datetime, %__MODULE__{} = duration) do
    shifted_date = add_months(DateTime.to_date(datetime), duration.months)

    {:ok, shifted_datetime} =
      DateTime.new(shifted_date, DateTime.to_time(datetime), datetime.time_zone)

    DateTime.add(shifted_datetime, duration.seconds, :second)
  end

  @spec add_to_time(Time.t(), t()) :: Time.t()
  def add_to_time(%Time{} = time, %__MODULE__{} = duration) do
    total_seconds =
      rem(
        time.hour * 3_600 + time.minute * 60 + time.second + duration.seconds,
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
end
