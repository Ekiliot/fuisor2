import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';
import dotenv from 'dotenv';

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

/**
 * Read email template from file
 * @param {string} templateName - Name of the template file
 * @returns {Promise<string>} Template content
 */
async function readEmailTemplate(templateName) {
  try {
    // Try to read from src/templates directory first (most reliable)
    const templatesPath = path.join(__dirname, '..', 'templates', templateName);
    if (fs.existsSync(templatesPath)) {
      return fs.promises.readFile(templatesPath, 'utf-8');
    }
    
    // Fallback: try from project root
    const templatePath = path.join(process.cwd(), templateName);
    if (fs.existsSync(templatePath)) {
      return fs.promises.readFile(templatePath, 'utf-8');
    }
    
    // Fallback: try relative to utils directory
    const relativePath = path.join(__dirname, '..', '..', templateName);
    if (fs.existsSync(relativePath)) {
      return fs.promises.readFile(relativePath, 'utf-8');
    }
    
    throw new Error(`Email template not found: ${templateName}`);
  } catch (error) {
    console.error(`Error reading email template ${templateName}:`, error);
    throw error;
  }
}

/**
 * Replace placeholders in template with actual values
 * @param {string} template - Template content
 * @param {object} variables - Key-value pairs for replacement
 * @returns {string} Template with replaced values
 */
function replaceTemplateVariables(template, variables) {
  let result = template;
  for (const [key, value] of Object.entries(variables)) {
    // Support both {{ VARIABLE }} and {{VARIABLE}} formats
    const regex = new RegExp(`{{\\s*${key}\\s*}}`, 'g');
    result = result.replace(regex, value);
  }
  return result;
}

/**
 * Send OTP email using Resend API or fallback to console
 * @param {string} email - Recipient email
 * @param {string} otpCode - OTP code to send
 * @param {string} type - Type of OTP email: 'password_change' or 'password_reset'
 * @returns {Promise<void>}
 */
export async function sendOTPEmail(email, otpCode, type = 'password_change') {
  try {
    // Determine template file based on type
    let templateFile;
    let subject;
    
    if (type === 'password_reset') {
      templateFile = 'password_reset_otp.html';
      subject = 'Your Password Reset Verification Code - SONET';
    } else {
      templateFile = 'password_change_otp.html';
      subject = 'Your Password Change Verification Code - SONET';
    }
    
    // Read the email template from file
    const template = await readEmailTemplate(templateFile);
    
    // Replace placeholders
    const htmlContent = replaceTemplateVariables(template, {
      OTP_CODE: otpCode
    });
    
    const resendApiKey = process.env.RESEND_API_KEY;
    
    if (resendApiKey) {
      // Use Resend API to send email
      const response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${resendApiKey}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          from: process.env.RESEND_FROM_EMAIL || 'SONET <noreply@sonet.app>',
          to: [email],
          subject: subject,
          html: htmlContent,
        }),
      });
      
      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(`Resend API error: ${JSON.stringify(errorData)}`);
      }
      
      const result = await response.json();
      console.log(`[EMAIL] ${type} OTP sent successfully to ${email} via Resend:`, result.id);
      return;
    }
    
    // Fallback: Log OTP when email service is not configured
    // Only log in development mode for security
    if (process.env.NODE_ENV === 'development') {
      console.log(`[EMAIL] Resend API key not configured. ${type} OTP for ${email}: ${otpCode}`);
      console.log(`[EMAIL] To enable email sending, set RESEND_API_KEY in environment variables`);
    } else {
      console.warn(`[EMAIL] Email service not configured. OTP code generated but not sent.`);
      console.warn(`[EMAIL] Please configure RESEND_API_KEY to enable email delivery.`);
    }
    
  } catch (error) {
    console.error('Error sending OTP email:', error);
    // Don't throw error, just log it so the flow continues
    // The OTP is still saved in the database and can be retrieved if needed
    console.log(`[EMAIL] Fallback: ${type} OTP for ${email}: ${otpCode}`);
  }
}

