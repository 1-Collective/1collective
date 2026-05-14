-- The logos bucket has bucket.public = true, which already makes individual
-- object URLs publicly fetchable WITHOUT any SELECT policy. The "logos: public read"
-- SELECT policy is redundant for object fetches but allows clients to LIST all
-- files in the bucket - that's the warning. Drop the policy.

drop policy if exists "logos: public read" on storage.objects;
