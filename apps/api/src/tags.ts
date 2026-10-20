import type pg from "pg";

export function normalizeTagName(name: string): string {
  return name.trim();
}

/** Resolve names within the authenticated user's namespace, handling concurrent creation. */
export async function resolveTagIds(client: pg.PoolClient, userId: string, names: readonly string[]): Promise<string[]> {
  const uniqueNames = [...new Map(names.map(normalizeTagName).filter(Boolean)
    .map(name => [name.toLocaleLowerCase(), name])).values()];
  const ids: string[] = [];
  for (const name of uniqueNames) {
    const result = await client.query<{ id: string }>(
      `insert into tags(user_id,name) values($1,$2)
       on conflict (user_id,lower(btrim(name))) do update set name=tags.name
       returning id`,
      [userId, name],
    );
    ids.push(result.rows[0].id);
  }
  return ids;
}
