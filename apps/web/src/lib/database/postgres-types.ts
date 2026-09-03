export const postgresDateText = {
  to: 1184,
  from: [1082, 1114, 1184],
  serialize: (value: string | Date) =>
    value instanceof Date ? value.toISOString() : value,
  parse: (value: string) => value,
};
