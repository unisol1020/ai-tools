import http from "node:http";

export function fetchOrders(since: Date, cb: (err: Error | null, body?: string) => void) {
  http.get(`http://api.example.com/orders?since=${since.toISOString()}`, (res) => {
    let body = "";
    res.on("data", (chunk) => (body += chunk));
    res.on("end", () => cb(null, body));
  }).on("error", cb);
}
