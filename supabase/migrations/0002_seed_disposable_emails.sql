-- ════════════════════════════════════════════════════════════════
-- Seed: disposable email blocklist
-- Source: github.com/disposable-email-domains/disposable-email-domains (subset)
-- ════════════════════════════════════════════════════════════════

INSERT INTO disposable_email_domains (domain) VALUES
  ('10minutemail.com'), ('10minutemail.net'), ('20minutemail.com'),
  ('30minutemail.com'), ('33mail.com'), ('emailondeck.com'),
  ('guerrillamail.com'), ('guerrillamail.net'), ('guerrillamail.org'),
  ('mailinator.com'), ('mailinator.net'), ('maildrop.cc'),
  ('mailnesia.com'), ('mintemail.com'), ('mohmal.com'),
  ('mytemp.email'), ('nada.email'), ('nwytg.net'),
  ('sharklasers.com'), ('spam4.me'), ('spamgourmet.com'),
  ('temp-mail.org'), ('tempmail.com'), ('tempmail.net'),
  ('tempmailaddress.com'), ('tempr.email'), ('throwawaymail.com'),
  ('trashmail.com'), ('trashmail.net'), ('trashmail.de'),
  ('yopmail.com'), ('yopmail.net'), ('yopmail.fr'),
  ('dispostable.com'), ('fakeinbox.com'), ('getairmail.com'),
  ('inboxbear.com'), ('jetable.org'), ('mailcatch.com'),
  ('mailexpire.com'), ('mailforspam.com'), ('mailtemp.info'),
  ('moakt.com'), ('mt2015.com'), ('mvrht.net'),
  ('odaymail.com'), ('opayq.com'), ('owlpic.com'),
  ('rcpt.at'), ('rppkn.com'), ('rmqkr.net'),
  ('soodonims.com'), ('spambog.com'), ('spambox.us'),
  ('superrito.com'), ('thankyou2010.com'), ('throwam.com'),
  ('tradermail.info'), ('vmailing.info'), ('walala.org'),
  ('wegwerfemail.de'), ('wuwuwa.com'), ('zehnminutenmail.de'),
  ('mailcuk.com'), ('email60.com'), ('mailtome.de'),
  ('mailmoat.com'), ('33mail.de'), ('spam.la'),
  ('einrot.com'), ('spambox.org'), ('wegwerf-email.de')
ON CONFLICT (domain) DO NOTHING;

-- Reference: production deployments should sync from the upstream list weekly
-- https://raw.githubusercontent.com/disposable-email-domains/disposable-email-domains/master/disposable_email_blocklist.conf
