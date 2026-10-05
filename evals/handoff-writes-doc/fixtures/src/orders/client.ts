export type Order = { id: string; total: number };

export async function fetchOrders(since: Date): Promise<Order[]> {
  const res = await fetch(`https://api.example.com/orders?since=${since.toISOString()}`);
  if (!res.ok) throw new Error(`orders api ${res.status}`);
  return res.json();
}
