// ====================================================================
// RoadWatch Supabase Edge Function: send-status-email
// Sends idempotent status update emails to reporters via configurable provider (Resend, SendGrid, etc.)
// Secrets (set via `supabase secrets set`):
// - RESEND_API_KEY (or SENDGRID_API_KEY)
// - EMAIL_FROM (optional, defaults to "RoadWatch <notifications@roadwatch.org>" or "onboarding@resend.dev")
// - SUPABASE_URL & SUPABASE_SERVICE_ROLE_KEY (provided automatically by Supabase)
// ====================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// In-memory cache to prevent duplicate email dispatches for the exact same event
const recentDispatches = new Map<string, number>();
const DEDUPLICATION_WINDOW_MS = 60 * 1000; // 60 seconds

interface EmailPayload {
  complaint_id: string;
  status: string; // 'Submitted', 'Verified', 'Accepted', 'Work Started', 'Repair In Progress', 'Completed', 'Rejected'
  reporter_user_id: string;
  reporter_email?: string;
  category?: string;
  address?: string;
  community_user_name?: string;
  progress_percentage?: number;
  progress_note?: string;
  notification_id?: string;
  app_url?: string;
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL");
    const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");

    if (!supabaseUrl || !supabaseServiceKey) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Supabase environment configuration missing on server.",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
      );
    }

    const supabaseAdmin = createClient(supabaseUrl, supabaseServiceKey);
    const body: EmailPayload = await req.json();

    const {
      complaint_id,
      status,
      reporter_user_id,
      reporter_email,
      category = "Road Damage",
      address = "Reported Location",
      community_user_name = "Community Repair Team",
      progress_percentage,
      progress_note,
      notification_id,
      app_url,
    } = body;

    if (!complaint_id || !status || !reporter_user_id) {
      return new Response(
        JSON.stringify({
          success: false,
          error: "Missing required fields: complaint_id, status, and reporter_user_id are required.",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 400 }
      );
    }

    console.log(`[send-status-email] Processing status update "${status}" for complaint "${complaint_id}", reporter "${reporter_user_id}"`);

    // 1. Resolve authentic submitter user ID and details from public.reports table
    let authenticReporterId = reporter_user_id;
    let authenticComplaintRef = complaint_id;
    let authenticCategory = category;
    let authenticAddress = address;

    try {
      const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(complaint_id);
      let reportRow = null;
      if (isUuid) {
        const { data } = await supabaseAdmin
          .from("reports")
          .select("id, user_id, complaint_id, title, issue_type, address")
          .eq("id", complaint_id)
          .maybeSingle();
        reportRow = data;
      }
      if (!reportRow) {
        const { data } = await supabaseAdmin
          .from("reports")
          .select("id, user_id, complaint_id, title, issue_type, address")
          .eq("complaint_id", complaint_id)
          .maybeSingle();
        reportRow = data;
      }

      if (reportRow) {
        if (reportRow.complaint_id) authenticComplaintRef = reportRow.complaint_id;
        if (reportRow.issue_type) authenticCategory = reportRow.issue_type;
        if (reportRow.address) authenticAddress = reportRow.address;
        if (reportRow.user_id && /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(reportRow.user_id.trim())) {
          authenticReporterId = reportRow.user_id.trim();
          console.log(`[send-status-email] ✅ Resolved original submitter from public.reports: ${authenticReporterId} (ref: ${authenticComplaintRef})`);
        }
      }
    } catch (err) {
      console.warn("[send-status-email] Warning querying reports table:", err);
    }

    // 2. Resolve Reporter Email securely from Supabase Auth (Never hardcoded)
    let recipientEmail: string | null = null;
    let recipientName = "Citizen Reporter";

    try {
      const { data: userData, error: userError } = await supabaseAdmin.auth.admin.getUserById(authenticReporterId);
      if (!userError && userData?.user?.email) {
        recipientEmail = userData.user.email;
        const meta = userData.user.user_metadata || {};
        recipientName = meta.full_name || meta.name || meta.display_name || "Citizen Reporter";
        console.log(`[send-status-email] ✅ Resolved registered email from Auth admin: ${recipientEmail}`);
      }
    } catch (err) {
      console.warn("[send-status-email] Warning querying auth.admin.getUserById:", err);
    }

    // Fallback: If not found, try DB helper function get_user_email
    if (!recipientEmail) {
      try {
        const { data: emailData } = await supabaseAdmin.rpc("get_user_email", {
          p_user_id: authenticReporterId,
        });
        if (emailData && typeof emailData === "string" && emailData.includes("@")) {
          recipientEmail = emailData.trim();
          console.log(`[send-status-email] ✅ Resolved registered email from get_user_email RPC: ${recipientEmail}`);
        }
      } catch (err) {
        console.warn("[send-status-email] Warning querying fallback email RPC:", err);
      }
    }

    // Fallback: Query user_profiles table
    if (!recipientEmail || recipientName === "Citizen Reporter") {
      try {
        const { data: profileData } = await supabaseAdmin
          .from("user_profiles")
          .select("email, full_name")
          .eq("user_id", authenticReporterId)
          .maybeSingle();

        if (profileData) {
          if (!recipientEmail && profileData.email && profileData.email.includes("@")) {
            recipientEmail = profileData.email.trim();
          }
          if (profileData.full_name) {
            recipientName = profileData.full_name;
          }
        }
      } catch (err) {
        console.warn("[send-status-email] Warning querying user_profiles:", err);
      }
    }

    // Fallback: Check caller-provided reporter_email
    if (!recipientEmail && reporter_email && reporter_email.includes("@")) {
      recipientEmail = reporter_email.trim();
    }

    if (!recipientEmail) {
      console.error(`[send-status-email] ❌ Failed to resolve registered email for reporter user ID: ${authenticReporterId}`);
      
      // Update notification record with failure if notification_id exists
      if (notification_id) {
        try {
          await supabaseAdmin
            .from("notifications")
            .update({
              email_status: "failed",
              email_error: `Could not resolve registered email for reporter ID: ${authenticReporterId}`,
            })
            .eq("id", notification_id);
        } catch (_) {}
      }

      return new Response(
        JSON.stringify({
          success: false,
          error: `Could not resolve registered email for reporter ID: ${authenticReporterId}`,
          email_status: "failed",
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 404 }
      );
    }

    const normalizedStatus = status.trim().toLowerCase();

    // 3. Idempotency Check: Prevent duplicate emails for the same event
    const deduplicationKey = `${authenticComplaintRef}:${normalizedStatus}:${recipientEmail}`;
    const lastSentAt = recentDispatches.get(deduplicationKey);
    const now = Date.now();

    if (lastSentAt && (now - lastSentAt) < DEDUPLICATION_WINDOW_MS) {
      console.log(`[send-status-email] ⚠️ Duplicate email delivery suppressed for: "${deduplicationKey}" (sent ${now - lastSentAt}ms ago)`);
      return new Response(
        JSON.stringify({
          success: true,
          email_status: "skipped",
          message: "Duplicate email suppressed; already sent recently.",
          recipient: recipientEmail,
          complaint_id: authenticComplaintRef,
        }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 4. Build Subject and Content based on Status
    let subject = "";
    let headline = "";
    let bodyText = "";
    let nextStepsText = "";
    let statusBadgeColor = "#2563EB";

    if (normalizedStatus.includes("submitted")) {
      subject = `RoadWatch: Complaint Submitted Successfully - ${complaint_id}`;
      headline = "Complaint Submitted Successfully";
      statusBadgeColor = "#2563EB";
      bodyText = `Thank you for taking action! Your road hazard complaint <strong>${complaint_id}</strong> for <strong>${category}</strong> has been successfully registered in the RoadWatch system.`;
      nextStepsText = "Your complaint is now live for community inspection and peer voting. Local citizens and volunteer crews can review, verify, and schedule repairs.";
    } else if (normalizedStatus.includes("verified")) {
      subject = `RoadWatch: Your complaint has been verified - ${complaint_id}`;
      headline = "Complaint Verified";
      statusBadgeColor = "#16A34A";
      bodyText = `Your reported complaint <strong>${complaint_id}</strong> has been inspected and confirmed by community members as a genuine issue.`;
      nextStepsText = "Your complaint is now queued for local community volunteer teams and repair crews to accept and schedule repair work.";
    } else if (normalizedStatus.includes("rejected") || normalizedStatus.includes("fake")) {
      subject = `RoadWatch: Complaint Status Update - ${complaint_id}`;
      headline = "Complaint Marked as Rejected";
      statusBadgeColor = "#DC2626";
      bodyText = `Your reported complaint <strong>${complaint_id}</strong> was audited by community inspectors and was marked as rejected or unverified.`;
      nextStepsText = "If you believe this issue was rejected by mistake, please verify the road location and submit a new report with clear site photos in the RoadWatch app.";
    } else if (normalizedStatus.includes("accepted")) {
      subject = `RoadWatch: Repair accepted for your complaint - ${complaint_id}`;
      headline = "Repair Work Accepted";
      statusBadgeColor = "#0284C7";
      bodyText = `Great news! <strong>${community_user_name}</strong> has officially accepted your complaint <strong>${complaint_id}</strong> for repair.`;
      nextStepsText = "Repair work will begin shortly. Real-time repair tracking, crew updates, and site photos are now available in your RoadWatch app.";
    } else if (normalizedStatus.includes("work started") || normalizedStatus.includes("progress") || normalizedStatus.includes("repair")) {
      const pct = progress_percentage != null ? progress_percentage.toFixed(0) : "In Progress";
      subject = `RoadWatch: Repair progress updated to ${pct}% - ${complaint_id}`;
      headline = `Repair Work Progress (${pct}%)`;
      statusBadgeColor = "#EA580C";
      const pctText = progress_percentage != null ? ` (Progress: ${progress_percentage.toFixed(0)}%)` : "";
      bodyText = `Repair crew member <strong>${community_user_name}</strong> has posted a new progress update for complaint <strong>${complaint_id}</strong>${pctText}.`;
      if (progress_note) {
        bodyText += `<br/><br/><strong>Crew Update Note:</strong> "${progress_note}"`;
      }
      nextStepsText = "Crew members are updating progress on site. You can track milestone photos in your RoadWatch Tracking screen.";
    } else if (normalizedStatus.includes("completed")) {
      subject = `RoadWatch: Repair completed for your complaint - ${complaint_id}`;
      headline = "Repair 100% Completed";
      statusBadgeColor = "#16A34A";
      bodyText = `The repair work for complaint <strong>${complaint_id}</strong> has been completed and verified on site!`;
      nextStepsText = "Please open the RoadWatch app to view the after-repair photo, verify the completed work, and submit your citizen rating and feedback.";
    } else {
      subject = `RoadWatch: Complaint Status Updated to ${status} - ${complaint_id}`;
      headline = `Status: ${status}`;
      bodyText = `Your complaint <strong>${complaint_id}</strong> has been updated to status: <strong>${status}</strong>.`;
      nextStepsText = "You can track the latest updates directly in your RoadWatch app.";
    }

    const openRoadWatchUrl = app_url || Deno.env.get("ROADWATCH_APP_URL") || "https://roadwatch.app";

    // 4. Build Responsive HTML Email Template
    const htmlBody = `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <title>${subject}</title>
      </head>
      <body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #F8FAFC; margin: 0; padding: 24px; color: #1E293B;">
        <div style="max-width: 600px; margin: 0 auto; background-color: #FFFFFF; border-radius: 16px; overflow: hidden; box-shadow: 0 4px 6px -1px rgba(0, 0, 0, 0.1); border: 1px solid #E2E8F0;">
          
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #1E3A8A 0%, #2563EB 100%); padding: 32px 24px; text-align: center; color: #FFFFFF;">
            <div style="display: inline-block; background-color: rgba(255, 255, 255, 0.2); padding: 8px 16px; border-radius: 20px; font-size: 13px; font-weight: 600; margin-bottom: 12px; letter-spacing: 0.5px;">
              🛣️ ROADWATCH COMMUNITY SYSTEM
            </div>
            <h1 style="margin: 0; font-size: 24px; font-weight: 800; letter-spacing: -0.5px;">${headline}</h1>
          </div>

          <!-- Body -->
          <div style="padding: 32px 24px;">
            <p style="font-size: 16px; line-height: 1.6; margin-top: 0;">
              Hello <strong>${recipientName}</strong>,
            </p>
            <p style="font-size: 15px; line-height: 1.6; color: #334155;">
              ${bodyText}
            </p>

            <!-- Complaint Details Card -->
            <div style="background-color: #F1F5F9; border-radius: 12px; padding: 20px; margin: 24px 0; border: 1px solid #CBD5E1;">
              <table style="width: 100%; border-collapse: collapse; font-size: 14px;">
                <tr>
                  <td style="padding: 6px 0; color: #64748B; font-weight: 600; width: 35%;">Complaint ID:</td>
                  <td style="padding: 6px 0; font-weight: 700; color: #0F172A;">${complaint_id}</td>
                </tr>
                <tr>
                  <td style="padding: 6px 0; color: #64748B; font-weight: 600;">Category:</td>
                  <td style="padding: 6px 0; color: #0F172A;">${category}</td>
                </tr>
                <tr>
                  <td style="padding: 6px 0; color: #64748B; font-weight: 600;">Location:</td>
                  <td style="padding: 6px 0; color: #0F172A;">${address}</td>
                </tr>
                <tr>
                  <td style="padding: 6px 0; color: #64748B; font-weight: 600;">Current Status:</td>
                  <td style="padding: 6px 0;">
                    <span style="display: inline-block; background-color: ${statusBadgeColor}; color: #FFFFFF; padding: 3px 10px; border-radius: 12px; font-size: 12px; font-weight: 700;">
                      ${status}
                    </span>
                  </td>
                </tr>
              </table>
            </div>

            <!-- Next Steps -->
            <div style="background-color: #EFF6FF; border-left: 4px solid #3B82F6; padding: 16px; border-radius: 0 8px 8px 0; margin-bottom: 24px;">
              <h4 style="margin: 0 0 6px 0; color: #1D4ED8; font-size: 14px; font-weight: 700;">Next Steps:</h4>
              <p style="margin: 0; font-size: 13px; line-height: 1.5; color: #1E40AF;">
                ${nextStepsText}
              </p>
            </div>

            <!-- Call to Action Link & Clear Instructions -->
            <div style="text-align: center; margin: 28px 0 20px 0;">
              <a href="${openRoadWatchUrl}" style="display: inline-block; background-color: #2563EB; color: #FFFFFF; font-weight: 700; font-size: 15px; text-decoration: none; padding: 12px 28px; border-radius: 8px; box-shadow: 0 4px 6px -1px rgba(37, 99, 235, 0.2);">
                Open RoadWatch App
              </a>
              <p style="font-size: 13px; color: #64748B; margin-top: 12px; line-height: 1.5;">
                Or open the RoadWatch app on your device to inspect photos, view live progress, and track community votes.
              </p>
            </div>

            <p style="font-size: 14px; color: #64748B; line-height: 1.5; margin-top: 24px;">
              Thank you for contributing to safer roads in your community.
            </p>
          </div>

          <!-- Footer -->
          <div style="background-color: #F8FAFC; border-top: 1px solid #E2E8F0; padding: 20px 24px; text-align: center; font-size: 12px; color: #94A3B8;">
            <p style="margin: 0;">RoadWatch Citizen & Community Infrastructure Portal</p>
            <p style="margin: 4px 0 0 0;">This is an automated notification sent to your registered email address.</p>
          </div>
        </div>
      </body>
      </html>
    `;

    // 5. Send Email via Configurable Provider
    const resendApiKey = Deno.env.get("RESEND_API_KEY");
    const sendgridApiKey = Deno.env.get("SENDGRID_API_KEY");
    const fromAddress = Deno.env.get("EMAIL_FROM") || "RoadWatch <onboarding@resend.dev>";

    let emailSent = false;
    let emailProviderError: string | null = null;
    let providerUsed = "none";

    if (resendApiKey) {
      providerUsed = "resend";
      try {
        const resendRes = await fetch("https://api.resend.com/emails", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${resendApiKey}`,
          },
          body: JSON.stringify({
            from: fromAddress,
            to: [recipientEmail],
            subject: subject,
            html: htmlBody,
          }),
        });

        if (resendRes.ok) {
          const resData = await resendRes.json();
          console.log(`[send-status-email] ✅ Resend delivered email to ${recipientEmail}, id: ${resData.id}`);
          emailSent = true;
        } else {
          const errText = await resendRes.text();
          emailProviderError = `Resend API Error (${resendRes.status}): ${errText}`;
          console.error(`[send-status-email] ❌ ${emailProviderError}`);
        }
      } catch (err: any) {
        emailProviderError = `Resend Exception: ${err.message || err}`;
        console.error(`[send-status-email] ❌ ${emailProviderError}`);
      }
    } else if (sendgridApiKey) {
      providerUsed = "sendgrid";
      try {
        const sendgridRes = await fetch("https://api.sendgrid.com/v3/mail/send", {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${sendgridApiKey}`,
          },
          body: JSON.stringify({
            personalizations: [{ to: [{ email: recipientEmail }] }],
            from: { email: fromAddress.includes("<") ? fromAddress.replace(/.*<([^>]+)>.*/, "$1") : fromAddress },
            subject: subject,
            content: [{ type: "text/html", value: htmlBody }],
          }),
        });

        if (sendgridRes.status >= 200 && sendgridRes.status < 300) {
          console.log(`[send-status-email] ✅ SendGrid delivered email to ${recipientEmail}`);
          emailSent = true;
        } else {
          const errText = await sendgridRes.text();
          emailProviderError = `SendGrid API Error (${sendgridRes.status}): ${errText}`;
          console.error(`[send-status-email] ❌ ${emailProviderError}`);
        }
      } catch (err: any) {
        emailProviderError = `SendGrid Exception: ${err.message || err}`;
        console.error(`[send-status-email] ❌ ${emailProviderError}`);
      }
    } else {
      // Neither RESEND_API_KEY nor SENDGRID_API_KEY is configured
      emailProviderError = "Email provider secret (RESEND_API_KEY or SENDGRID_API_KEY) not set in Supabase Edge Function environment.";
      console.warn(`[send-status-email] ⚠️ ${emailProviderError}`);
    }

    // 6. Update Notification in public.notifications
    const finalEmailStatus = emailSent ? "sent" : "failed";

    if (emailSent) {
      recentDispatches.set(deduplicationKey, Date.now());
      // Clean up entries older than 5 minutes
      for (const [k, timestamp] of recentDispatches.entries()) {
        if (Date.now() - timestamp > 5 * 60 * 1000) {
          recentDispatches.delete(k);
        }
      }
    }

    try {
      if (notification_id) {
        await supabaseAdmin
          .from("notifications")
          .update({
            email_status: finalEmailStatus,
            email_recipient: recipientEmail,
            email_error: emailSent ? null : emailProviderError,
          })
          .eq("id", notification_id);
      }
    } catch (notifUpdateErr) {
      console.warn("[send-status-email] Notice: could not update email_status on notifications table (columns may not exist):", notifUpdateErr);
    }

    return new Response(
      JSON.stringify({
        success: emailSent,
        email_status: finalEmailStatus,
        recipient: recipientEmail,
        provider: providerUsed,
        error: emailSent ? null : emailProviderError,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err: any) {
    console.error("[send-status-email] Unhandled Edge Function exception:", err);
    return new Response(
      JSON.stringify({
        success: false,
        email_status: "failed",
        error: `Edge function exception: ${err.message || err}`,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" }, status: 500 }
    );
  }
});
