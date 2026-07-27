export function formatInteger(value: number): string {
  const rounded = Math.round(value);
  const sign = rounded < 0 ? "-" : "";
  const digits = String(Math.abs(rounded));
  return `${sign}${digits.replace(/\B(?=(\d{3})+(?!\d))/g, ".")}`;
}

export function formatEUR(value: number): string {
  return `${formatInteger(value)}\u00a0€`;
}
