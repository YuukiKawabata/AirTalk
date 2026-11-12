/** Conservative pilot rules, not a claim of comprehensive automated moderation. */
export function permittedMessage(text: string): boolean {
  const value = text.normalize("NFKC").toLowerCase();
  // The pilot does not support external invitations, contact harvesting or links.
  if (/(https?:\/\/|www\.|discord\.gg\/|t\.me\/|line\.me\/)/u.test(value))
    return false;
  if (/[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}/u.test(value)) return false;
  if (/(.)\1{29,}/u.test(value)) return false;
  if (
    ["死ね", "殺してやる", "kill yourself", "i will kill you"].some((term) =>
      value.includes(term),
    )
  )
    return false;
  return true;
}
