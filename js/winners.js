import {supabase,requireConfiguration} from './supabase.js'
export async function publicWinners(){requireConfiguration();const {data,error}=await supabase.rpc('public_winners');if(error)throw error;return data}
export async function publishWinners(eventId,count){
  requireConfiguration();
  const cleanCount = (typeof count === 'number' ? count : parseInt(count, 10)) || 3;
  const {data,error}=await supabase.rpc('publish_winners',{p_event_id:eventId,p_count:cleanCount});
  if(error)throw error;
  return data;
}

