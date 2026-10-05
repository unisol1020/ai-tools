import { TABLE_WIDTH, cell } from "./theme";

export type Refund = { id: string; orderId: string; amount: number };

export function RefundsTable({ refunds }: { refunds: Refund[] }) {
  return (
    <table style={{ width: TABLE_WIDTH }}>
      <thead>
        <tr><th style={cell}>Id</th><th style={cell}>Order</th><th style={cell}>Amount</th></tr>
      </thead>
      <tbody>
        {refunds.map((r) => (
          <tr key={r.id}><td style={cell}>{r.id}</td><td style={cell}>{r.orderId}</td><td style={cell}>{r.amount}</td></tr>
        ))}
      </tbody>
    </table>
  );
}
