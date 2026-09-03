import {supabase,requireConfiguration} from './supabase.js'
export async function setRoundStatus(roundId,status){requireConfiguration();const {data,error}=await supabase.rpc('set_round_status',{p_round_id:roundId,p_status:status});if(error)throw error;return data}
export async function announceRound(roundId){requireConfiguration();const {data,error}=await supabase.rpc('announce_round_result',{p_round_id:roundId});if(error)throw error;return data}
export async function generateRoundTwo(eventId,method,topN=null,teamIds=[]){requireConfiguration();const {data,error}=await supabase.rpc('generate_round_two',{p_event_id:eventId,p_method:method,p_top_n:topN,p_team_ids:teamIds});if(error)throw error;return data}
