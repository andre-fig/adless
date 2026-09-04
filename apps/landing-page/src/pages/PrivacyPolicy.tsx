import LegalLayout from "./LegalLayout";

const PrivacyPolicy = () => (
  <LegalLayout title="Privacy Policy" updatedAt="August 26, 2026">
    <p>
      Adless is developed by Orbe Works. This Privacy Policy explains what happens
      when you use the Adless iOS app and website.
    </p>

    <h2>What Adless does</h2>
    <p>
      All DNS queries selected by iOS for Adless are sent over HTTPS to the
      Adless DNS service. The edge checks the active blocklist: blocked names are
      answered there and are not sent to a resolver; permitted names are sent as
      encrypted DNS-over-HTTPS messages to Cloudflare DNS first, with Quad9 as a
      fallback. Only DNS uses Adless infrastructure. Websites, videos, messages,
      and downloads go directly from your device to their destinations.
    </p>

    <h2>Information we collect</h2>
    <p>
      Orbe Works does not collect or retain account information, browsing history,
      DNS query history, advertising identifiers, or payment information through
      Adless. The app has no account or login. The service stores only an
      aggregate blocked total associated with an anonymous installation token;
      it does not store domains, DNS packets, or an application-level history.
      Because a DoH GET can carry the DNS wire message in the URL and the
      installation token is part of the endpoint path, Cloudflare may process
      technical request metadata under its infrastructure and logging systems;
      Adless does not enable application-level request logging or send these
      values to Sentry.
      Permitted DNS queries are transmitted to Cloudflare DNS or Quad9 only to
      obtain DNS answers; their handling is governed by their own policies.
      Adless uses Sentry for crash and performance diagnostics, but does not send
      DNS queries, domain names, browsing history, or the installation token to it.
    </p>

    <h2>Third-party services</h2>
    <p>
      Apple processes App Store purchases and subscriptions under Apple&apos;s own
      terms and privacy policy. Cloudflare provides infrastructure for the Adless
      edge service. Cloudflare DNS and Quad9 process permitted DNS-over-HTTPS
      queries to return DNS answers under their respective service and privacy
      policies. Sentry, operated by Functional Software, Inc., processes crash
      and performance diagnostics for reliability. Adless downloads public,
      static blocklist files from the public Railway landing service; hosting providers can process
      standard technical connection information for those requests.
    </p>

    <h2>Data retention and deletion</h2>
    <p>
      Adless does not maintain a user account or domain history. The aggregate
      counter is removed from the app's data when you delete it. The
      device-bound Keychain token may remain in the Keychain after uninstall on
      the same device; it is not migrated to a new device. The service retains
      only aggregate counter data needed to show the total and operate the
      service; it is not a domain history. This version has no token-deletion
      endpoint. Apple
      manages purchase records and subscription history. Adless does not sell
      data or use DNS queries for advertising.
    </p>

    <h2>Important limitations</h2>
    <p>
      DNS encryption protects the connection to the configured service; Adless
      does not promise anonymity, hide your IP address, prevent infrastructure
      logs, or guarantee that your internet provider cannot infer destinations.
      iCloud Private Relay, IP address tracking limits, another DNS profile, a
      VPN, a captive portal, or network policy can change which resolver iOS uses.
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
