import LegalLayout from "./LegalLayout";

const PrivacyPolicy = () => (
  <LegalLayout title="Privacy Policy" updatedAt="August 20, 2026">
    <p>
      Adless is developed by Orbe Works. This Privacy Policy explains what happens
      when you use the Adless iOS app and website.
    </p>

    <h2>What Adless does</h2>
    <p>
      Adless uses Apple&apos;s Network Extension DNS Proxy to process DNS queries on
      your device and block domains included in the active blocklist. DNS queries
      are handled locally by the app and are not sent to an Orbe Works server or a
      remote VPN service.
    </p>

    <h2>Information we collect</h2>
    <p>
      Orbe Works does not collect account information, browsing history, DNS query
      history, device identifiers, advertising identifiers, analytics, or payment
      information through Adless. The app has no account, login, or custom backend.
      Blocking statistics are stored locally in the app&apos;s protected storage.
    </p>

    <h2>Third-party services</h2>
    <p>
      Apple processes App Store purchases and subscriptions under Apple&apos;s own
      terms and privacy policy. Adless downloads public, static blocklist files
      from GitHub Pages. Those requests can include standard technical connection
      information handled by the hosting provider, such as an IP address.
    </p>

    <h2>Data retention and deletion</h2>
    <p>
      Adless does not maintain a user account or server-side user record. Local
      blocklists, subscription state, and blocking statistics can be removed by
      deleting the app. Apple manages purchase records and subscription history.
    </p>

    <h2>Children</h2>
    <p>
      Adless is not directed at children and does not knowingly collect personal
      information from children.
    </p>

    <h2>Contact</h2>
    <p>
      Questions about this policy can be sent to{" "}
      <a href="mailto:a_figueiredo@icloud.com">a_figueiredo@icloud.com</a>.
    </p>
  </LegalLayout>
);

export default PrivacyPolicy;
