import {supabase,requireConfiguration} from './supabase.js'

export async function listTeams(eventId,search=''){
  requireConfiguration();
  let q=supabase.from('teams').select('id,team_name,team_code,phone_number,created_at,round_teams(id,round_id,qualified,rounds(round_number))').eq('event_id',eventId).order('team_code');
  if(search)q=q.or(`team_name.ilike.%${search}%,team_code.ilike.%${search}%`);
  const {data,error}=await q;
  if(error)throw error;
  return data;
}

export async function currentTeam(){
  const data=await getParticipantPayload();
  return data.team;
}

export async function getParticipantPayload(){
  requireConfiguration();
  const {data:{session}}=await supabase.auth.getSession();
  const teamId=session?.user?.user_metadata?.team_id;
  if(!teamId)throw new Error('not_authorized');
  const {data,error}=await supabase.rpc('participant_dashboard',{p_team_id:teamId});
  if(error)throw error;
  return data;
}
