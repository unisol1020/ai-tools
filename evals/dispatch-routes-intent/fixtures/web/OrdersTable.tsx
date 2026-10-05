import type { Order } from "../src/api/orders";
import { TABLE_WIDTH, cell } from "./theme";

export function OrdersTable({ orders }: { orders: Order[] }) {
  return (
    <table style={{ width: TABLE_WIDTH }}>
      <thead>
        <tr><th style={cell}>Id</th><th style={cell}>Customer</th><th style={cell}>Total</th><th style={cell}>Status</th></tr>
      </thead>
      <tbody>
        {orders.map((o) => (
          <tr key={o.id}><td style={cell}>{o.id}</td><td style={cell}>{o.customer}</td><td style={cell}>{o.total}</td><td style={cell}>{o.status}</td></tr>
        ))}
      </tbody>
    </table>
  );
}
