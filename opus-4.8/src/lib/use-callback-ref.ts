import { useCallback, useEffect, useRef } from "react";

/**
 * Returns a stable callback identity that always invokes the latest version of
 * the provided function. Useful for effects that should not re-run when the
 * callback's closure changes.
 */
export function useCallbackRef<T extends (...args: never[]) => unknown>(
  callback: T
): T {
  const ref = useRef(callback);

  useEffect(() => {
    ref.current = callback;
  });

  return useCallback(
    ((...args) => ref.current(...args)) as T,
    []
  );
}
