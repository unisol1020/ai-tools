import { findOrders, totalsByStatus } from "../repo/orders-repo";
import type { Order } from "../api/orders";

export type OrdersSummary = { orders: Order[]; totals: Record<string, number>; topStatus: string };

export function summarize(customer?: string): OrdersSummary {
  const orders = findOrders(customer);
  const totals = totalsByStatus(orders);
  const topStatus = Object.entries(totals).sort((a, b) => b[1] - a[1])[0][0];
  return { orders, totals, topStatus };
}
