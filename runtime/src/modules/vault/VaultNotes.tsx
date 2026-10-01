import React, {memo, useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {Alert, FlatList, Pressable, ScrollView, StyleSheet, TextInput, View} from 'react-native';
import type {Host, ModuleContext} from '@modula/module-sdk';
import {saveData, textEditable, type NotePage, type NoteRow} from './model';
import {normalizeNoteRows} from './rows';
import {moduleTheme, type ModuleTheme} from '../../ui/theme';
import {blockModels} from '../../ui/blocks';
import {DocumentBlocks, LoadingRow, ModuleButton, ModuleFallback, ThemedText} from '../../ui/components';

type Props = {context: ModuleContext; host: Host; lifecycle: string};

export function VaultNotes({context, host, lifecycle}: Props) {
  const initialNoteID = context.initialPath?.match(/^\/note\/([A-Za-z0-9._:-]+)(?:\/edit)?$/)?.[1];
  const [editor, setEditor] = useState<{record?: NoteRow} | null>(context.initialPath === '/new' ? {} : null);
  const [revision, setRevision] = useState(0);
  const theme = useMemo(() => moduleTheme(context.environment), [context.environment]);
  const openProfile = useCallback(() => {
    void host.request('navigation.open', {route: 'profile', userId: context.userID ?? 'me'}).catch(() => {});
  }, [host, context.userID]);
  return <View style={[styles.root, {backgroundColor: theme.colors.canvas}]}>
    <View style={[styles.meta, {paddingHorizontal: theme.spacing.lg, paddingTop: theme.spacing.xs, gap: theme.spacing.xs}]}>
      {/* Diagnostics kept for UI tests; visually reduced to a caption. */}
      <ThemedText theme={theme} role="caption" secondary testID="vault.environment">
        {context.environment.colorScheme} · OLED {String(context.environment.oled)} · {context.environment.accent}</ThemedText>
      <ThemedText theme={theme} role="caption" secondary testID="vault.lifecycle">{lifecycle}</ThemedText>
    </View>
    {!context.userID
      ? <ModuleFallback theme={theme} title="Sign in to open your Vault" message="Sign in through native Settings, then reopen Vault Notes."/>
      : editor
        ? <Editor key={editor.record?.record_id ?? 'new'} record={editor.record} host={host} theme={theme}
            close={() => { setEditor(null); setRevision(value => value + 1); }}/>
        : <Notes key={revision} host={host} theme={theme} initialNoteID={initialNoteID}
            open={record => setEditor({record})} create={() => setEditor({})}/>}
    <View style={{paddingHorizontal: theme.spacing.lg, paddingVertical: theme.spacing.xs, borderTopWidth: StyleSheet.hairlineWidth,
      borderTopColor: theme.colors.border, backgroundColor: theme.colors.canvas}}>
      <ModuleButton theme={theme} title="Open my native Profile" variant="secondary" onPress={openProfile}/>
    </View>
  </View>;
}

const NoteCard = memo(function NoteCard({row, theme, open}: {row: NoteRow; theme: ModuleTheme; open: (row: NoteRow) => void}) {
  const preview = row.data.plainTextProjection.trim();
  return <Pressable accessibilityRole="button" accessibilityLabel={row.data.title}
    accessibilityHint={preview ? preview.slice(0, 120) : 'Empty note'} onPress={() => open(row)}
    style={({pressed}) => [styles.card, {backgroundColor: theme.colors.surface, borderRadius: theme.radius.card,
      padding: theme.spacing.md, gap: theme.spacing.xs, minHeight: 76, borderColor: theme.colors.border,
      opacity: pressed && !theme.reduceMotion ? 0.85 : 1}]}>
    <ThemedText theme={theme} role="headline" numberOfLines={2}>{row.data.title}</ThemedText>
    <ThemedText theme={theme} secondary numberOfLines={2}>{preview || 'No content yet'}</ThemedText>
  </Pressable>;
});

function Notes({host, theme, initialNoteID, open, create}: {
  host: Host; theme: ModuleTheme; initialNoteID?: string; open: (row: NoteRow) => void; create: () => void;
}) {
  const [rows, setRows] = useState<NoteRow[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const alive = useRef(true);
  const generation = useRef(0);
  const reportedDataReady = useRef(false);
  const appliedInitialPath = useRef(false);
  async function load(next?: string) {
    const request = ++generation.current; setLoading(true); setError(null);
    try {
      const page = await host.request<NotePage>('backend.records.list', {collection: 'note', ...(next ? {cursor: next} : {})});
      if (alive.current && generation.current === request) {
        setRows(old => next ? [...old, ...normalizeNoteRows(page?.items, old)] : normalizeNoteRows(page?.items));
        setCursor(typeof page?.nextCursor === 'string' ? page.nextCursor : null);
        if (!next && initialNoteID && !appliedInitialPath.current) {
          appliedInitialPath.current = true;
          const local = normalizeNoteRows(page?.items).find(row => row.record_id === initialNoteID);
          if (local) open(local);
          else void host.request<NoteRow>('backend.records.get', {collection: 'note', recordID: initialNoteID})
            .then(row => { const [safe] = normalizeNoteRows([row]); if (safe) open(safe); }).catch(() => {});
        }
        if (!reportedDataReady.current) { reportedDataReady.current = true; void host.request('diagnostics.dataReady').catch(() => {}); }
      }
    } catch (error) { if (alive.current && generation.current === request) setError(error instanceof Error ? error.message : 'Notes could not load.'); }
    finally { if (alive.current && generation.current === request) setLoading(false); }
  }
  useEffect(() => { alive.current = true; void load(); return () => { alive.current = false; generation.current++; }; }, [host, initialNoteID]);
  const visible = useMemo(() => rows.filter(row => !row.data.archived), [rows]);
  const renderItem = useCallback(({item}: {item: NoteRow}) => <NoteCard row={item} theme={theme} open={open}/>, [theme, open]);
  const gap = theme.spacing.sm;
  return <FlatList
    data={visible}
    keyExtractor={row => row.record_id}
    renderItem={renderItem}
    initialNumToRender={12}
    windowSize={7}
    removeClippedSubviews
    keyboardShouldPersistTaps="handled"
    contentContainerStyle={{padding: theme.spacing.lg, paddingTop: theme.spacing.sm}}
    ItemSeparatorComponent={() => <View style={{height: gap}}/>}
    ListHeaderComponent={<View style={{gap: theme.spacing.md, marginBottom: theme.spacing.md}}>
      <ThemedText theme={theme} role="largeTitle" accessibilityRole="header">Your notes</ThemedText>
      <View style={[styles.actions, {gap: theme.spacing.sm}]}>
        <View style={styles.flex}><ModuleButton theme={theme} title="New Note" onPress={create}/></View>
        <View style={styles.flex}><ModuleButton theme={theme} title="Reload notes" variant="secondary" disabled={loading} onPress={() => void load()}/></View>
      </View>
      {loading && <LoadingRow theme={theme} label="Loading notes"/>}
      {error && <ModuleFallback theme={theme} title="Notes couldn’t load" message={error} action={{title: 'Try again', onPress: () => void load()}}/>}
      {!loading && !error && <ThemedText theme={theme} role="caption" secondary testID="vault.loaded">Notes loaded</ThemedText>}
    </View>}
    ListEmptyComponent={!loading && !error
      ? <ModuleFallback theme={theme} title="Your Vault is empty" message="Create your first note." testID="vault.empty"/> : undefined}
    ListFooterComponent={<View style={{gap: theme.spacing.sm, marginTop: theme.spacing.md}}>
      {cursor && <ModuleButton theme={theme} title="Load more notes" variant="secondary" disabled={loading} onPress={() => void load(cursor)}/>}
    </View>}
  />;
}

function Editor({record, host, theme, close}: {record?: NoteRow; host: Host; theme: ModuleTheme; close: () => void}) {
  const [current, setCurrent] = useState(record);
  const [title, setTitle] = useState(record?.data.title ?? '');
  const [text, setText] = useState(record?.data.plainTextProjection ?? '');
  const [busy, setBusy] = useState(Boolean(record));
  const [status, setStatus] = useState(record ? 'Loading note…' : 'New note');
  const alive = useRef(true);
  useEffect(() => {
    alive.current = true;
    if (record) void host.request<NoteRow>('backend.records.get', {collection: 'note', recordID: record.record_id}).then(raw => {
      const [row] = normalizeNoteRows([raw]);
      if (!alive.current) return;
      if (!row) { setStatus('This note could not be read. Close and try again.'); return; }
      setCurrent(row); setTitle(row.data.title); setText(row.data.plainTextProjection); setStatus('Ready to edit');
    }).catch(() => { if (alive.current) setStatus('Could not reload the note. Close and try again.'); })
      .finally(() => { if (alive.current) setBusy(false); });
    return () => { alive.current = false; };
  }, [host, record?.record_id]);
  async function save() {
    if (busy) return; setBusy(true); setStatus('Saving…');
    try {
      const data = saveData(title, text, current?.data);
      const row = await host.request<NoteRow>(current ? 'backend.records.update' : 'backend.records.create', current
        ? {collection: 'note', recordID: current.record_id, expectedRevision: current.revision, data} : {collection: 'note', data});
      if (alive.current) { setCurrent(normalizeNoteRows([row])[0] ?? current); setStatus('Saved'); }
      void host.request('haptics.selection').catch(() => {});
    } catch (error) { if (alive.current) setStatus(error instanceof Error ? error.message : 'The note could not be saved.'); }
    finally { if (alive.current) setBusy(false); }
  }
  async function remove() {
    if (!current || busy) return; setBusy(true);
    try { await host.request('backend.records.delete', {collection: 'note', recordID: current.record_id, expectedRevision: current.revision}); if (alive.current) close(); }
    catch (error) { if (alive.current) { setStatus(error instanceof Error ? error.message : 'Could not move note to Trash.'); setBusy(false); } }
  }
  const editable = !current || textEditable(current.data.document);
  const blocks = useMemo(() => editable ? [] : blockModels(current?.data.document), [editable, current?.data.document]);
  const input = {color: theme.colors.text, backgroundColor: theme.colors.surface, borderRadius: theme.radius.control,
    padding: theme.spacing.md, borderColor: theme.colors.border, fontSize: theme.type.body};
  return <ScrollView contentContainerStyle={{padding: theme.spacing.lg, gap: theme.spacing.md}} keyboardShouldPersistTaps="handled">
    <View style={styles.start}><ModuleButton theme={theme} title="Notes" variant="secondary" onPress={close} disabled={busy}/></View>
    <TextInput accessibilityLabel="Note title" testID="vault.title" value={title} onChangeText={setTitle} editable={!busy}
      maxLength={240} placeholder="Note title" placeholderTextColor={theme.colors.textSecondary} allowFontScaling
      maxFontSizeMultiplier={theme.maxFontSizeMultiplier} style={[styles.input, input, {fontSize: theme.type.title, fontWeight: '600'}]}/>
    {editable
      ? <TextInput accessibilityLabel="Note content" testID="vault.content" value={text} onChangeText={setText} editable={!busy}
          multiline placeholder="Write a note" placeholderTextColor={theme.colors.textSecondary} allowFontScaling
          maxFontSizeMultiplier={theme.maxFontSizeMultiplier} style={[styles.input, styles.editor, input]}/>
      : <View style={{gap: theme.spacing.sm}}>
          <View style={[styles.input, input]}><DocumentBlocks theme={theme} blocks={blocks}/></View>
          <ThemedText theme={theme} role="caption" secondary>This note contains rich content. Its structure is preserved; the full editor will follow.</ThemedText>
        </View>}
    <ThemedText theme={theme} role="caption" secondary accessibilityRole="alert" testID="vault.saveStatus">{status}</ThemedText>
    <ModuleButton theme={theme} title="Save note" onPress={() => void save()} disabled={busy}/>
    {current && <ModuleButton theme={theme} title="Move to Trash" variant="destructive" disabled={busy}
      onPress={() => Alert.alert('Move note to Trash?', 'The note remains recoverable in Vault.', [
        {text: 'Cancel', style: 'cancel'}, {text: 'Move to Trash', style: 'destructive', onPress: () => void remove()}])}/>}
  </ScrollView>;
}

const styles = StyleSheet.create({
  root: {flex: 1},
  meta: {flexDirection: 'row', flexWrap: 'wrap'},
  actions: {flexDirection: 'row'},
  flex: {flex: 1},
  start: {alignSelf: 'flex-start'},
  card: {borderWidth: StyleSheet.hairlineWidth},
  input: {minHeight: 48, borderWidth: StyleSheet.hairlineWidth},
  editor: {minHeight: 180, textAlignVertical: 'top'},
});
