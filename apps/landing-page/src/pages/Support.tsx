import LegalLayout from "./LegalLayout";

const Support = () => (
  <LegalLayout title="Adless Support" updatedAt="August 20, 2026">
    <p>
      Adless is an on-device DNS protection app for iPhone. It does not use a
      remote VPN server or an Adless account.
    </p>

    <h2>Before contacting support</h2>
    <ul>
      <li>Make sure the subscription is active in your Apple Account.</li>
      <li>Open Adless and tap the main button to enable protection.</li>
      <li>Check Settings → General → VPN &amp; Device Management for the Adless DNS profile.</li>
      <li>If the network changes, turn protection off and on once to reload the local DNS proxy.</li>
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
