import { fetchOrders } from "./legacy-client";

export function syncOrders(since: Date) {
  fetchOrders(since, (err, body) => {
    if (err) throw err;
    console.log(`synced ${JSON.parse(body ?? "[]").length} orders`);
  });
}
