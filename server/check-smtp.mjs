import { existsSync } from 'node:fs';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { smtpTransport } from './mailer.mjs';

const root = fileURLToPath(new URL('..',import.meta.url));
const env = resolve(root,'.env');
if (existsSync(env)) process.loadEnvFile(env);
const transport = smtpTransport();
if (!transport) {
  console.error('SMTP settings are incomplete. Fill SMTP_HOST, SMTP_USER and SMTP_PASS in .env.');
  process.exitCode=1;
} else {
  try {
    await transport.verify();
    console.log('SMTP connection, TLS and authentication passed. No email was sent.');
  } catch (error) {
    console.error('SMTP verification failed (' + (error.code || 'connection error') + '). Check the server settings and App Password.');
    process.exitCode=1;
  } finally { transport.close(); }
}
