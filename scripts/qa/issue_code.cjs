const fs = require("fs");
const tokens = JSON.parse(fs.readFileSync("/tmp/qa_tokens_cache_02e.json"));

async function run() {
  const businessId = "3e000000-0000-4000-8000-000000000101";
  const jobId = "84ee5a11-0e80-4925-97ce-fb285c87f1be";
  const res = await fetch(`http://127.0.0.1:18083/api/v1/merchant/businesses/${businessId}/delivery-jobs/${jobId}/pickup-code`, {
    method: "POST",
    headers: { "Authorization": "Bearer " + tokens["+919990000172"] }
  });
  const data = await res.json();
  console.log(JSON.stringify(data));
}
run();
