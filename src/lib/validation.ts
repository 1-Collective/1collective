import { z } from "zod";

export type ActionResult<T = void> =
  | { ok: true; data: T }
  | { ok: false; error: string; fieldErrors?: Record<string, string[]> };

export function actionOk(): ActionResult<void>;
export function actionOk<T>(data: T): ActionResult<T>;
export function actionOk<T>(data?: T): ActionResult<T> {
  return { ok: true, data: data as T };
}

export function actionError(
  error: string,
  fieldErrors?: Record<string, string[]>
): ActionResult<never> {
  return fieldErrors ? { ok: false, error, fieldErrors } : { ok: false, error };
}

export function parseForm<S extends z.ZodType>(
  schema: S,
  formData: FormData
):
  | { ok: true; data: z.infer<S> }
  | { ok: false; error: string; fieldErrors: Record<string, string[]> } {
  const obj: Record<string, FormDataEntryValue | FormDataEntryValue[]> = {};
  for (const [key, value] of formData.entries()) {
    const existing = obj[key];
    if (existing === undefined) {
      obj[key] = value;
    } else if (Array.isArray(existing)) {
      existing.push(value);
    } else {
      obj[key] = [existing, value];
    }
  }
  const parsed = schema.safeParse(obj);
  if (parsed.success) return { ok: true, data: parsed.data };
  const flattened = parsed.error.flatten();
  return {
    ok: false,
    error: "Validation failed",
    fieldErrors: flattened.fieldErrors as Record<string, string[]>,
  };
}
