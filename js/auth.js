import {supabase,requireConfiguration} from './supabase.js'

function persistRole(role){
  if(!role)return;
  try{
    localStorage.setItem('eventx_auth_role', role);
  }catch{}
}

async function edgeFunctionErrorMessage(error, fallback){
  let message=error?.message||fallback;
  try{
    if(error?.context){
      const errJson=await error.context.json();
      if(errJson?.error)message=errJson.error;
    }
  }catch{}
  return message;
}

export async function registerCoordinator({username,name,password}){
  requireConfiguration();
  const {data,error}=await supabase.functions.invoke('coordinator-register',{body:{username:username.trim(),name:name.trim(),password}});
  if(error)throw new Error(await edgeFunctionErrorMessage(error,'Account creation could not be completed.'));
  if(data?.error)throw new Error(data.error);
  const {error:sessionError}=await supabase.auth.setSession({access_token:data.access_token,refresh_token:data.refresh_token});
  if(sessionError)throw sessionError;
  persistRole('coordinator');
  return data;
}

export async function loginCoordinator(username,password){
  requireConfiguration();
  const {data,error}=await supabase.functions.invoke('coordinator-login',{body:{username:username.trim(),password}});
  if(error)throw new Error(await edgeFunctionErrorMessage(error,'invalid_credentials'));
  if(data?.error)throw new Error(data.error);
  const {error:sessionError}=await supabase.auth.setSession({access_token:data.access_token,refresh_token:data.refresh_token});
  if(sessionError)throw sessionError;
  persistRole('coordinator');
  return data;
}

export async function participantRegister(payload){
  requireConfiguration();
  const {data,error}=await supabase.functions.invoke('register-team',{body:payload});
  if(error)throw new Error(await edgeFunctionErrorMessage(error,'Team registration could not be completed.'));
  if(data?.error)throw new Error(data.error);
  await setParticipantSession(data);
  persistRole('participant');
  return data.team;
}

export async function participantLogin(payload){
  requireConfiguration();
  const {data,error}=await supabase.functions.invoke('participant-login',{body:payload});
  if(error)throw new Error(await edgeFunctionErrorMessage(error,'Login could not be completed.'));
  if(data?.error)throw new Error(data.error);
  await setParticipantSession(data);
  persistRole('participant');
  return data.team;
}

async function setParticipantSession(data){
  const {error}=await supabase.auth.setSession({access_token:data.access_token,refresh_token:data.refresh_token});
  if(error)throw error;
}

export async function logout(){
  try{
    localStorage.removeItem('eventx_auth_role');
  }catch{}
  // Reset the cached session promise so any future login gets a fresh resolution.
  sessionPromise=null;
  if(supabase)await supabase.auth.signOut();
  location.href='/eventx.html';
}

const LOG='[EventX Auth]';

// Module-level promise so concurrent callers share the same resolution.
// Set to null after a logout so the next login triggers a fresh resolution.
let sessionPromise = null;

function getActiveSession(){
  if(!supabase)return Promise.resolve(null);
  if(sessionPromise)return sessionPromise;

  sessionPromise = new Promise(resolve=>{
    let settled=false;

    function finish(value){
      if(settled)return;
      settled=true;
      clearTimeout(timer);
      // Unsubscribe after the current tick to avoid re-entry.
      setTimeout(()=>subscription?.unsubscribe?.(),0);
      resolve(value);
    }

    // 3-second hard ceiling so the page never hangs if INITIAL_SESSION
    // somehow never fires (e.g. Supabase is down on startup).
    const timer=setTimeout(()=>{
      console.log(LOG,'session wait timed out after 3s — treating as logged out');
      finish(null);
    },3000);

    const {data:{subscription}}=supabase.auth.onAuthStateChange((event,session)=>{
      console.log(LOG,'onAuthStateChange',event,session?.user?.id||null);
      // INITIAL_SESSION: fired once on every page load with the stored session
      //   (or null if there is no stored session).
      // SIGNED_IN: fired after a successful login or token refresh.
      // SIGNED_OUT: fired after an explicit logout or refresh-token expiry.
      if(event==='INITIAL_SESSION'||event==='SIGNED_IN'){
        finish(session?.user ? session : null);
      } else if(event==='SIGNED_OUT'){
        finish(null);
      }
    });
  });

  return sessionPromise;
}

export async function requireRole(role){
  requireConfiguration();
  const session = await getActiveSession();

  if(!session||!session.user){
    console.log(LOG,'no session, redirecting to login');
    location.href=role==='coordinator'?'/pages/coordinator-login.html':'/pages/participant-login.html';
    return null;
  }

  const storedRole=localStorage.getItem('eventx_auth_role');
  const metadataRole=session.user?.user_metadata?.role || session.user?.app_metadata?.role;
  const userRole=metadataRole || storedRole;

  if(userRole && userRole !== role){
    console.log(LOG,'role mismatch, redirecting');
    location.href=role==='coordinator'?'/pages/coordinator-login.html':'/pages/participant-login.html';
    return null;
  }

  localStorage.setItem('eventx_auth_role',role);
  return session.user;
}
