export type Clock = () => number;

export const createInMemoryFixedWindowRateLimiter = (clock: Clock = Date.now) => {
  const buckets = new Map<string, { startedAt: number; count: number }>();
  const consume = (
    key: string,
    limit: number,
    windowMs: number,
  ): { allowed: boolean; retryAfterMs: number } => {
    const now = clock();
    const startedAt = Math.floor(now / windowMs) * windowMs;
    const existing = buckets.get(key);
    const bucket = existing?.startedAt === startedAt ? existing : { startedAt, count: 0 };
    bucket.count += 1;
    buckets.set(key, bucket);
    return {
      allowed: bucket.count <= limit,
      retryAfterMs: bucket.count <= limit ? 0 : Math.max(1, startedAt + windowMs - now),
    };
  };
  return { consume };
};
