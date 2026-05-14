type LogLevel = "info" | "warn" | "error";
type LogContext = Record<string, unknown>;

function emit(level: LogLevel, message: string, context: LogContext = {}) {
  const line = JSON.stringify({
    ts: new Date().toISOString(),
    level,
    msg: message,
    ...context,
  });
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.log(line);
}

export const log = {
  info: (msg: string, ctx?: LogContext) => emit("info", msg, ctx),
  warn: (msg: string, ctx?: LogContext) => emit("warn", msg, ctx),
  error: (msg: string, ctx?: LogContext) => emit("error", msg, ctx),
};
