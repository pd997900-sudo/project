// ====================================================================
// RoadWatch Supabase Edge Function: send-roadwatch-email (DEACTIVATED)
// Reverted per user request. Email delivery has been undone.
// In-app notifications are processed directly via public.notifications.
// ====================================================================

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  return new Response(
    JSON.stringify({
      success: false,
      message: "send-roadwatch-email has been deactivated. Email delivery changes were reverted.",
    }),
    {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 410,
    }
  );
});
