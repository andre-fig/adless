import LegalLayout from "./LegalLayout";

const PrivacyPolicy = () => (
  <LegalLayout title="Privacy Policy" updatedAt="August 20, 2026">
    <p>
      Adless is developed by Orbe Works. This Privacy Policy explains what happens
      when you use the Adless iOS app and website.
    </p>

    <h2>What Adless does</h2>
    <p>
      Adless uses Apple&apos;s Network Extension Packet Tunnel to process DNS queries on
      your device and block domains included in the active blocklist. Blocked
      names are answered locally. Permitted DNS queries are sent as encrypted
      DNS-over-HTTPS wire messages to Cloudflare DNS or Quad9 so they can be
      resolved. Adless does not operate a server or a remote VPN service.
    </p>

    <h2>Information we collect</h2>
    <p>
      Orbe Works does not collect or retain account information, browsing history,
      DNS query history, advertising identifiers, or payment information through
      Adless. The app has no account, login, or custom backend. Blocking statistics
      are stored locally in the app&apos;s protected storage. Permitted DNS queries
      are transmitted to the configured third-party DNS providers only to obtain
      DNS answers; their handling is governed by their own privacy policies.
      Adless does use Sentry for crash and performance diagnostics; it receives
      technical diagnostic data such as app version, operating system, device
      model, stack traces, and timing data. Adless does not send DNS queries,
      domain names, browsing history, or a user identity to Sentry.
    </p>

    <h2>Third-party services</h2>
    <p>
      Apple processes App Store purchases and subscriptions under Apple&apos;s own
      terms and privacy policy. Cloudflare DNS and Quad9 process permitted
      DNS-over-HTTPS queries to return DNS answers under their respective service
      and privacy policies. Sentry, operated by Functional Software, Inc.,
      processes crash and performance diagnostics for reliability purposes under its
      privacy policy. Adless downloads public, static blocklist files from GitHub
      Pages. Those requests can include standard technical connection information
      handled by the hosting provider, such as an IP address.
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
