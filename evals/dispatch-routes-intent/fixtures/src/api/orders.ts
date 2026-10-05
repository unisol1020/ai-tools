import express from "express";
import { summarize } from "../services/orders-service";

export type Order = { id: string; customer: string; total: number; status: string };

export const router = express.Router();

router.get("/orders", (req, res) => {
  const summary = summarize(req.query.customer as string | undefined);
  res.json({ orders: summary.orders, totals: summary.totals, topStatus: summary.topStatus });
});
