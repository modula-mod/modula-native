import React, {useEffect, useRef, useState} from 'react';
import {ActivityIndicator, Alert, Button, Pressable, ScrollView, StyleSheet, Text, TextInput, View} from 'react-native';
import type {Host, ModuleContext} from '@modula/module-sdk';
import {saveData, textEditable, type NotePage, type NoteRow} from './model';
type Props = {context: ModuleContext; host: Host; lifecycle: string};
export function VaultNotes({context,host,lifecycle}: Props) {
  const initialNoteID = context.initialPath?.match(/^\/note\/([A-Za-z0-9._:-]+)(?:\/edit)?$/)?.[1];
  const [editor,setEditor] = useState<{record?: NoteRow} | null>(context.initialPath === '/new' ? {} : null);
  const [revision,setRevision] = useState(0);
  const dark = context.environment.colorScheme === 'dark';
  const colors = {background:context.environment.oled?'#000':dark?'#15191a':'#f5f8f8',text:dark?'#f5f8f8':'#172426',card:dark?'#242e30':'#fff',accent:context.environment.accent};
  return <View style={[styles.root,{backgroundColor:colors.background}]}>
    <View style={styles.context}>
      <Text style={{color:colors.text}} testID="vault.environment">{context.environment.colorScheme} · OLED {String(context.environment.oled)} · {context.environment.accent}</Text>
      <Text style={{color:colors.text}} testID="vault.lifecycle">{lifecycle}</Text>
    </View>
    {!context.userID ? <Text style={[styles.message,{color:colors.text}]}>Sign in through native Settings to open your Vault.</Text> : editor
      ? <Editor key={editor.record?.record_id??'new'} record={editor.record} host={host} colors={colors} close={()=>{setEditor(null);setRevision(value=>value+1);}}/>
      : <Notes key={revision} host={host} colors={colors} initialNoteID={initialNoteID} open={record=>setEditor({record})} create={()=>setEditor({})}/>}
    <View style={styles.footer}><Button title="Open my native Profile" color={colors.accent} onPress={()=>{
      void host.request('navigation.open',{route:'profile',userId:context.userID??'me'}).catch(()=>{});
    }}/></View>
  </View>;
}
type Colors = {background:string;text:string;card:string;accent:string};
function Notes({host,colors,initialNoteID,open,create}:{host:Host;colors:Colors;initialNoteID?:string;open:(row:NoteRow)=>void;create:()=>void}) {
  const [rows,setRows] = useState<NoteRow[]>([]);
  const [cursor,setCursor] = useState<string|null>(null);
  const [loading,setLoading] = useState(true);
  const [error,setError] = useState<string|null>(null);
  const alive = useRef(true);
  const generation = useRef(0);
  const reportedDataReady = useRef(false);
  const appliedInitialPath = useRef(false);
  async function load(next?:string) {
    const request = ++generation.current;setLoading(true);setError(null);
    try {
      const page=await host.request<NotePage>('backend.records.list',{collection:'note',...(next?{cursor:next}:{})});
      if(alive.current && generation.current===request){
        setRows(old=>next?[...old,...page.items]:page.items);setCursor(page.nextCursor);
        if(!next&&initialNoteID&&!appliedInitialPath.current){
          appliedInitialPath.current=true;
          const local=page.items.find(row=>row.record_id===initialNoteID);
          if(local)open(local);
          else void host.request<NoteRow>('backend.records.get',{collection:'note',recordID:initialNoteID}).then(open).catch(()=>{});
        }
        if(!reportedDataReady.current){reportedDataReady.current=true;void host.request('diagnostics.dataReady').catch(()=>{});}
      }
    } catch(error) {if(alive.current && generation.current===request)setError(error instanceof Error?error.message:'Notes could not load.');}
    finally {if(alive.current && generation.current===request)setLoading(false);}
  }
  useEffect(()=>{alive.current=true;void load();return()=>{alive.current=false;generation.current++;};},[host,initialNoteID]);
  return <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
    <Text accessibilityRole="header" style={[styles.heading,{color:colors.text}]}>Your notes</Text>
    <View style={styles.actions}><Button title="New Note" color={colors.accent} onPress={create}/><Button title="Reload notes" color={colors.accent} disabled={loading} onPress={()=>void load()}/></View>
    {loading&&<ActivityIndicator accessibilityLabel="Loading notes" color={colors.accent}/>}
    {error&&<Text accessibilityRole="alert" style={{color:colors.text}}>{error}</Text>}
    {!loading&&!error&&rows.length===0&&<Text style={{color:colors.text}}>Your Vault is empty. Create your first note.</Text>}
    {!loading&&!error&&<Text testID="vault.loaded" style={{color:colors.text}}>Notes loaded</Text>}
    {rows.filter(row=>!row.data.archived).map(row=><Pressable key={row.record_id} accessibilityRole="button" accessibilityLabel={row.data.title} onPress={()=>open(row)} style={[styles.card,{backgroundColor:colors.card}]}>
      <Text style={[styles.title,{color:colors.text}]}>{row.data.title}</Text><Text numberOfLines={2} style={{color:colors.text}}>{row.data.plainTextProjection}</Text>
    </Pressable>)}
    {cursor&&<Button title="Load more notes" disabled={loading} onPress={()=>void load(cursor)}/>}
  </ScrollView>;
}
function Editor({record,host,colors,close}:{record?:NoteRow;host:Host;colors:Colors;close:()=>void}) {
  const [current,setCurrent]=useState(record);
  const [title,setTitle]=useState(record?.data.title??'');
  const [text,setText]=useState(record?.data.plainTextProjection??'');
  const [busy,setBusy]=useState(Boolean(record));
  const [status,setStatus]=useState(record?'Loading note…':'New note');
  const alive=useRef(true);
  useEffect(()=>{alive.current=true;
    if(record)void host.request<NoteRow>('backend.records.get',{collection:'note',recordID:record.record_id}).then(row=>{
      if(alive.current){setCurrent(row);setTitle(row.data.title);setText(row.data.plainTextProjection);setStatus('Ready to edit');}
    }).catch(()=>{if(alive.current)setStatus('Could not reload the note. Close and try again.');}).finally(()=>{if(alive.current)setBusy(false);});
    return()=>{alive.current=false;};
  },[host,record?.record_id]);
  async function save(){
    if(busy)return;setBusy(true);setStatus('Saving…');
    try {
      const data=saveData(title,text,current?.data);
      const row=await host.request<NoteRow>(current?'backend.records.update':'backend.records.create',current
        ?{collection:'note',recordID:current.record_id,expectedRevision:current.revision,data}:{collection:'note',data});
      if(alive.current){setCurrent(row);setStatus('Saved');}
      void host.request('haptics.selection').catch(()=>{});
    }catch(error){if(alive.current)setStatus(error instanceof Error?error.message:'The note could not be saved.');}
    finally{if(alive.current)setBusy(false);}
  }
  async function remove(){
    if(!current||busy)return;setBusy(true);
    try{await host.request('backend.records.delete',{collection:'note',recordID:current.record_id,expectedRevision:current.revision});if(alive.current)close();}
    catch(error){if(alive.current){setStatus(error instanceof Error?error.message:'Could not move note to Trash.');setBusy(false);}}
  }
  const editable=!current||textEditable(current.data.document);
  return <ScrollView contentContainerStyle={styles.content} keyboardShouldPersistTaps="handled">
    <Button title="Notes" onPress={close} disabled={busy} color={colors.accent}/>
    <TextInput accessibilityLabel="Note title" testID="vault.title" value={title} onChangeText={setTitle} editable={!busy} maxLength={240} placeholder="Note title" placeholderTextColor={colors.text} style={[styles.input,styles.title,{color:colors.text,backgroundColor:colors.card}]}/>
    <TextInput accessibilityLabel="Note content" testID="vault.content" value={text} onChangeText={setText} editable={!busy&&editable} multiline placeholder="Write a note" placeholderTextColor={colors.text} style={[styles.input,styles.editor,{color:colors.text,backgroundColor:colors.card}]}/>
    {!editable&&<Text style={{color:colors.text}}>This note contains rich content. Its structure is preserved; the full editor will follow.</Text>}
    <Text accessibilityRole="alert" testID="vault.saveStatus" style={{color:colors.text}}>{status}</Text>
    <Button title="Save note" onPress={()=>void save()} disabled={busy} color={colors.accent}/>
    {current&&<Button title="Move to Trash" color={colors.accent} disabled={busy} onPress={()=>Alert.alert('Move note to Trash?','The note remains recoverable in Vault.',[{text:'Cancel',style:'cancel'},{text:'Move to Trash',style:'destructive',onPress:()=>void remove()}])}/>}
  </ScrollView>;
}
const styles=StyleSheet.create({root:{flex:1},content:{padding:20,gap:16},context:{paddingHorizontal:20,paddingTop:8,gap:4},heading:{fontSize:28,fontWeight:'700'},title:{fontSize:19,fontWeight:'600'},actions:{flexDirection:'row',justifyContent:'space-between'},card:{padding:18,borderRadius:16,gap:8,minHeight:76},input:{padding:16,borderRadius:12,minHeight:48},editor:{minHeight:180,textAlignVertical:'top'},footer:{padding:8},message:{padding:24,fontSize:17}});
