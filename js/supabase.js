import { createClient } from '@supabase/supabase-js'

const url = import.meta.env.VITE_SUPABASE_URL
const key = import.meta.env.VITE_SUPABASE_ANON_KEY

export const isConfigured = Boolean(url && key && !url.includes('your-project'))
export const supabase = isConfigured
  ? createClient(url, key, { auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true } })
  : null

export function requireConfiguration() {
  if (!isConfigured) throw new Error('SETUP_REQUIRED')
}

export function friendlyError(error) {
  console.error("friendlyError input:", error);
  const messages = {
    SETUP_REQUIRED: 'Connect Supabase to use this feature. See the setup guide.',
    invalid_credentials: 'Those login details are not correct.',
    round_locked: 'This round is already locked.',
    not_authorized: 'You are not authorized to perform this action.',
    event_code_not_found: 'Event code is invalid.',
    team_name_already_registered: 'Team name already exists in this event.',
    invalid_phone: 'Phone number must be between 7 and 20 characters.',
    invalid_team_name: 'Team name must be between 2 and 120 characters.',
    team_not_in_round: 'This team is not qualified for this round.',
    round_not_found: 'Round not found.',
    invalid_time: 'Enter a valid time in minutes.seconds format.',
    invalid_team: 'Selected team does not belong to this event.',
    round_one_not_locked: 'Round 1 must be announced and locked before generating Round 2.',
    no_teams_selected: 'Please select at least one team for Round 2.',
    no_qualified_teams: 'No qualified teams found for Round 2.',
    invalid_top_n: 'Please specify a valid number of teams (at least 1).',
    final_result_not_announced: 'Final round results must be announced and locked before publishing winners.',
    winners_already_published: 'Winners have already been published for this event.',
    not_enough_final_results: 'No final scores found. Please enter scores and announce the round before publishing winners.',
    invalid_winner_count: 'Please select a valid winner count.',
    no_scores: 'Enter at least one score before announcing this round.',
    invalid_event_name: 'Event name must be between 2 and 120 characters.',
    invalid_rule: 'One of the scoring rules is invalid for this event.',
    invalid_quantity: 'All quantities must be zero or greater.',
  };

  if (error?.message && messages[error.message]) {
    return messages[error.message];
  }
  if (error?.code && messages[error.code]) {
    return messages[error.code];
  }
  if (error?.message && typeof error.message === 'string') {
    return error.message;
  }
  return 'Something went wrong. Please try again.';
}
