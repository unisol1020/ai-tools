import type { Order } from "../api/orders";

const rows: Order[] = [];

export function findOrders(customer?: string): Order[] {
  return customer ? rows.filter((r) => r.customer === customer) : rows;
}

export function totalsByStatus(orders: Order[]): Record<string, number> {
  return orders.reduce((acc, o) => ({ ...acc, [o.status]: (acc[o.status] ?? 0) + o.total }), {} as Record<string, number>);
}
