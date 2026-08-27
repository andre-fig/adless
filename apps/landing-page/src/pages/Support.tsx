import LegalLayout from "./LegalLayout";

const Support = () => (
  <LegalLayout title="Adless Support" updatedAt="August 26, 2026">
    <p>
      Adless is an encrypted DNS protection app for iPhone. It does not use an
      Adless account and does not proxy your general internet traffic.
    </p>

    <h2>Before contacting support</h2>
    <ul>
      <li>Make sure the subscription is active in your Apple Account.</li>
      <li>Open Adless and tap the main button to enable protection.</li>
      <li>Open Settings → General → VPN &amp; Network → DNS and enable the Adless DNS configuration if iOS asks for approval.</li>
      <li>When a network changes, iOS applies the saved DNS configuration when it remains available.</li>
    </ul>

    <h2>Contact us</h2>
    <p>
      Email <a href="mailto:a_figueiredo@icloud.com">a_figueiredo@icloud.com</a>{" "}
      with your iOS version and a short description of the issue. Please do not
      include passwords, payment details, or private browsing history.
    </p>
  </LegalLayout>
);

export default Support;
