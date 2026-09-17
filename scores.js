import {supabase,requireConfiguration} from './supabase.js'

export async function saveScore({roundId,teamId,totalTimeSeconds,details}){
  requireConfiguration();
  const {data,error}=await supabase.rpc('save_score',{
    p_round_id:roundId,
    p_team_id:teamId,
    p_total_time_seconds:totalTimeSeconds,
    p_score_details:Object.fromEntries(details.map(x=>[x.rule_key,x.quantity]))
  });
  if(error)throw error;
  return data;
}

export async function leaderboard(eventId){
  requireConfiguration();
  const {data,error}=await supabase.rpc('event_leaderboard',{p_event_id:eventId});
  if(error)throw error;
  return data;
}
