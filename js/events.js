import {supabase,requireConfiguration} from './supabase.js'
export async function listEvents(){requireConfiguration();const {data,error}=await supabase.from('events').select('id,event_name,event_code,point_format,status,created_at,teams(count),rounds(round_number,status)').order('created_at',{ascending:false});if(error)throw error;return data}
export async function getEvent(id){requireConfiguration();const {data,error}=await supabase.from('events').select('*,scoring_rules(*),rounds(*)').eq('id',id).single();if(error)throw error;return data}
export async function createEvent(eventName,pointFormat){requireConfiguration();const {data,error}=await supabase.rpc('create_event',{p_event_name:eventName,p_point_format:pointFormat});if(error)throw error;return data}
export async function dashboardStats(){requireConfiguration();const {data,error}=await supabase.rpc('coordinator_dashboard_stats');if(error)throw error;return data}
