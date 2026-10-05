import { useEffect, useState } from "react";
import type { Order } from "../src/api/orders";
import { OrdersTable } from "./OrdersTable";
import { RefundsTable, type Refund } from "./RefundsTable";

export function OrdersPage() {
  const [orders, setOrders] = useState<Order[]>([]);
  const [refunds, setRefunds] = useState<Refund[]>([]);

  useEffect(() => {
    fetch("/orders").then((r) => r.json()).then((body) => setOrders(body.orders));
    fetch("/refunds").then((r) => r.json()).then((body) => setRefunds(body.refunds));
  }, []);

  return (
    <main style={{ padding: 24 }}>
      <h1>Orders</h1>
      <OrdersTable orders={orders} />
      <h2>Refunds</h2>
      <RefundsTable refunds={refunds} />
    </main>
  );
}
