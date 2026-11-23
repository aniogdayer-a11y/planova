import nodemailer from 'nodemailer';

export function smtpTransport(env = process.env) {
  if (!env.SMTP_HOST || !env.SMTP_USER || !env.SMTP_PASS) return null;
  const port = Number(env.SMTP_PORT || 465);
  const secure = (env.SMTP_SECURE || (port === 465 ? 'true' : 'false')) === 'true';
  return nodemailer.createTransport({
    host:env.SMTP_HOST, port, secure, requireTLS:!secure,
    auth:{user:env.SMTP_USER, pass:env.SMTP_PASS},
    connectionTimeout:15_000, greetingTimeout:15_000, socketTimeout:20_000,
  });
}

export function smtpSender(env = process.env) {
  const transport = smtpTransport(env);
  if (!transport) return null;
  return async ({email, code, purpose='login'}) => transport.sendMail({
    from:env.SMTP_FROM || env.SMTP_USER, to:email,
    subject:purpose === 'password-changed' ? 'Your Planova password was changed'
      : purpose === 'reset' ? 'Reset your Planova password' : 'Your Planova verification code',
    text:purpose === 'password-changed'
      ? 'Your Planova password was changed. All sessions have been signed out. If you did not make this change, use Forgot password immediately to recover your account.'
      : 'Your Planova ' + (purpose === 'reset' ? 'password reset' : 'verification') + ' code is ' + code + '.\n\nIt expires in 10 minutes and can be used once. '
        + 'Do not share this code. If you did not request it, you can ignore this email.',
  });
}
