export type ResultError<Code extends string = string> = {
  code: Code;
  message: string;
};

export type Result<Value, Code extends string = string> =
  | { ok: true; value: Value }
  | { ok: false; error: ResultError<Code> };

export function ok<Value>(value: Value): Result<Value, never> {
  return { ok: true, value };
}

export function error<Code extends string>(
  code: Code,
  message: string,
): Result<never, Code> {
  return { ok: false, error: { code, message } };
}

export async function tryCatch<Value, Code extends string>(
  operation: () => Promise<Value>,
  mapError: (cause: unknown) => ResultError<Code> | null,
): Promise<Result<Value, Code>> {
  try {
    return ok(await operation());
  } catch (cause) {
    const mapped = mapError(cause);
    if (!mapped) throw cause;
    return { ok: false, error: mapped };
  }
}
