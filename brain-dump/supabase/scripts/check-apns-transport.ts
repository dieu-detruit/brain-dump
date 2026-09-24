// No credentials or device token. A 4xx from APNs verifies transport only, not delivery.
const response = await fetch("https://api.sandbox.push.apple.com/3/device/00", {
  method: "POST",
  body: "{}",
});
console.log("APNs HTTP status:", response.status);
console.log("APNs response:", await response.text());
if (response.status < 400 || response.status >= 500) throw new Error("Unexpected APNs probe response");
