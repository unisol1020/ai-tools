export type User = { id: string; email: string; password: string };

const users: User[] = [];

export async function findUserByEmail(email: string): Promise<User | undefined> {
  return users.find((u) => u.email === email);
}
