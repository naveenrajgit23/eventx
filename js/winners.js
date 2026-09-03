import {supabase,requireConfiguration} from './supabase.js'
export async function publicWinners(){requireConfiguration();const {data,error}=await supabase.from('published_winners').select('*').order('published_at',{ascending:false}).order('position');if(error)throw error;return data}
export async function publishWinners(eventId,count){requireConfiguration();const {data,error}=await supabase.rpc('publish_winners',{p_event_id:eventId,p_count:count});if(error)throw error;return data}
