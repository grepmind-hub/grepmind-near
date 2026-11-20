const fs = require("fs");
const tokens = JSON.parse(fs.readFileSync("/tmp/qa_tokens_cache_02e.json"));

async function run() {
  const orderId = "f9b8f5d4-ab36-47ff-ae19-9d573f605e01";
  const res = await fetch(`http://127.0.0.1:18083/api/v1/orders/${orderId}/delivery-code`, {
    method: "POST",
    headers: { "Authorization": "Bearer " + tokens["+919990000171"] }
  });
  const data = await res.json();
  console.log(JSON.stringify(data));
}
run();
