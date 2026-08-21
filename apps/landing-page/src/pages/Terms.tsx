import LegalLayout from "./LegalLayout";

const Terms = () => (
  <LegalLayout title="Terms of Use" updatedAt="August 20, 2026">
    <p>
      These Terms of Use govern your use of Adless, an on-device DNS filtering
      application developed by Orbe Works.
    </p>

    <h2>Subscriptions</h2>
    <p>
      Adless may be offered through monthly and annual auto-renewable
      subscriptions. A subscription includes the features shown in the app at the
      time of purchase. Any free trial, price, renewal date, and applicable taxes
      are displayed by Apple before purchase.
    </p>
    <p>
      Payment is charged to your Apple Account. Unless canceled through your Apple
      Account settings at least 24 hours before the end of the current period, a
      subscription renews automatically. Apple manages billing, refunds, and
      cancellation.
    </p>

    <h2>Use of the service</h2>
    <p>
      Adless provides local DNS-based blocking of domains identified by its
      blocklist. No filtering system can identify every ad, tracker, or domain, and
      blocking a domain can occasionally affect a website or app. You are
      responsible for deciding whether to keep the protection enabled.
    </p>

    <h2>Availability</h2>
    <p>
      We may update the blocklist, app, or service to improve reliability and
      security. The app keeps a valid local list and can continue using it when the
      network is unavailable, but uninterrupted operation cannot be guaranteed.
    </p>

    <h2>Contact</h2>
    <p>
      For support, contact{" "}
      <a href="mailto:a_figueiredo@icloud.com">a_figueiredo@icloud.com</a>.
    </p>
  </LegalLayout>
);

export default Terms;
