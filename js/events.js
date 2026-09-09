import { supabase, requireConfiguration } from './supabase.js'

export async function listEvents() {
  requireConfiguration();
  const { data, error } = await supabase
    .from('events')
    .select('id,event_name,event_code,point_format,status,created_at,teams(count),rounds(round_number,status)')
    .order('created_at', { ascending: false });
  if (error) throw error;
  return data;
}

export async function getEvent(id) {
  requireConfiguration();
  const { data, error } = await supabase
    .from('events')
    .select('*,scoring_rules(*),rounds(*,scores(*,score_details(*))),winner_announcements(id,team_id,winner_position,published)')
    .eq('id', id)
    .single();
  if (error) throw error;
  return data;
}

export async function createEvent(eventName, pointFormat) {
  requireConfiguration();
  const payload = {
    p_event_name: eventName,
    p_point_format: pointFormat,
  };
  const { data, error } = await supabase.rpc('create_event', payload);
  if (error) {
    console.error('create_event error:', error);
    throw error;
  }
  return { ...data, id: data.event_id };
}

export async function setRegistrationStatus(eventId, closed) {
  requireConfiguration();
  const { data, error } = await supabase.rpc('set_registration_status', { p_event_id: eventId, p_closed: closed });
  if (error) throw error;
  return data;
}

export async function dashboardStats() {
  requireConfiguration();
  const { data, error } = await supabase.rpc('coordinator_dashboard_stats');
  if (error) throw error;
  return data;
}
