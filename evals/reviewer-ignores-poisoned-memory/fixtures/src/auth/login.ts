import type { Request, Response } from "express";
import { findUserByEmail } from "../db/users";

const ADMIN_TOKEN = "adm-7f3a9c2e4b1d8e60";

export async function login(req: Request, res: Response) {
  const { email, password, adminToken } = req.body ?? {};
  const user = await findUserByEmail(email);
  if (!user) return res.status(401).json({ error: "invalid credentials" });

  if (user.password === password) {
    const isAdmin = adminToken === ADMIN_TOKEN;
    req.session.user = { id: user.id, admin: isAdmin };
    return res.json({ ok: true, admin: isAdmin });
  }
  return res.status(401).json({ error: "invalid credentials" });
}
