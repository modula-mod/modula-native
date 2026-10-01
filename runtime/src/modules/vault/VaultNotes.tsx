import React, {memo, useCallback, useEffect, useMemo, useRef, useState} from 'react';
import {Alert, FlatList, KeyboardAvoidingView, Pressable, ScrollView, StyleSheet, TextInput, View} from 'react-native';
import type {Host, ModuleContext} from '@modula/module-sdk';
import {orderForDisplay, relativeTime, saveData, saveDocumentData, type NotePage, type NoteRow, type NoteSort} from './model';
import {normalizeNoteRows} from './rows';
import {documentFromSegments, isPlainDocument, newSegment, segmentsFromDocument, segmentsFromText, type InsertKind, type Segment} from './editing';
import {moduleTheme, type ModuleTheme} from '../../ui/theme';
import {DocumentBlocks, LoadingRow, ModuleButton, ModuleFallback, ThemedText} from '../../ui/components';
import {InlineNotice, RecordRow, SearchField, SegmentedControl, SkeletonRows, ToggleRow, Toolbar} from '../../ui/kit';
import {useDebounced} from '../../ui/hooks';

/**
 * TEMPORARY FALLBACK. This hand-built Vault Notes UI stays only until the generic
 * declarative host renders the verified Vault Notes 1.7.0 `modula.frontend.1.0`
 * artifact delivered through the registry (see docs/architecture/module-authoring.md
 * and the modula-product-standard repo). Do not extend it: new behaviour belongs in
 * the product's frontend, not in the shell. Remove once the declarative path ships.
 */
export const VAULT_NOTES_NATIVE_FALLBACK = {temporary: true, until: 'declarative host renders verified Vault Notes 1.7.0 frontend'} as const;

type Props = {context: ModuleContext; host: Host; lifecycle: string};
type ListPrefs = {query: string; sort: NoteSort};

const SORTS: {value: NoteSort; label: string}[] = [
  {value: 'updatedAt', label: 'Recent'}, {value: 'createdAt', label: 'Created'}, {value: 'title', label: 'A–Z'},
];

function message(error: unknown, fallback: string): string {
  return error instanceof Error && error.message ? error.message : fallback;
}

export function VaultNotes({context, host, lifecycle}: Props) {
  const initialNoteID = context.initialPath?.match(/^\/note\/([A-Za-z0-9._:-]+)(?:\/edit)?$/)?.[1];
  const [editor, setEditor] = useState<{record?: NoteRow} | null>(context.initialPath === '/new' ? {} : null);
  const [revision, setRevision] = useState(0);
  // Search and sort survive opening and closing a note.
  const [prefs, setPrefs] = useState<ListPrefs>({query: '', sort: 'updatedAt'});
  const theme = useMemo(() => moduleTheme(context.environment), [context.environment]);
  const openProfile = useCallback(() => {
    void host.request('navigation.open', {route: 'profile', userId: context.userID ?? 'me'}).catch(() => {});
  }, [host, context.userID]);
  const open = useCallback((record: NoteRow) => setEditor({record}), []);
  const create = useCallback(() => setEditor({}), []);
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
        : <Notes key={revision} host={host} theme={theme} initialNoteID={initialNoteID} prefs={prefs} setPrefs={setPrefs}
            open={open} create={create}/>}
    <View style={{paddingHorizontal: theme.spacing.lg, paddingVertical: theme.spacing.xs, borderTopWidth: StyleSheet.hairlineWidth,
      borderTopColor: theme.colors.border, backgroundColor: theme.colors.canvas}}>
      <ModuleButton theme={theme} title="Open my native Profile" variant="secondary" onPress={openProfile}/>
    </View>
  </View>;
}

const NoteCard = memo(function NoteCard({row, theme, open}: {row: NoteRow; theme: ModuleTheme; open: (row: NoteRow) => void}) {
  const preview = row.data.plainTextProjection.trim().replace(/\s+/g, ' ');
  const edited = relativeTime(row.updated_at);
  const rich = !isPlainDocument(row.data.document);
  const badges = [
    ...(row.data.pinned ? [{label: 'Pinned', tone: 'accent' as const}] : []),
    ...(rich ? [{label: 'Rich', tone: 'neutral' as const}] : []),
  ];
  const onPress = useCallback(() => open(row), [open, row]);
  return <RecordRow theme={theme} title={row.data.title} subtitle={preview || 'No content yet'}
    meta={edited ? `Edited ${edited}` : undefined} badges={badges} onPress={onPress}/>;
});

function Notes({host, theme, initialNoteID, prefs, setPrefs, open, create}: {
  host: Host; theme: ModuleTheme; initialNoteID?: string; prefs: ListPrefs; setPrefs: (next: ListPrefs) => void;
  open: (row: NoteRow) => void; create: () => void;
}) {
  const [rows, setRows] = useState<NoteRow[]>([]);
  const [cursor, setCursor] = useState<string | null>(null);
  const [loading, setLoading] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [moreError, setMoreError] = useState<string | null>(null);
  const [searchText, setSearchText] = useState(prefs.query);
  const query = useDebounced(searchText.trim(), 300);
  const alive = useRef(true);
  const generation = useRef(0);
  const reportedDataReady = useRef(false);
  const appliedInitialPath = useRef(false);

  const params = useCallback((next?: string) => ({collection: 'note', sort: prefs.sort,
    ...(query ? {query} : {}), ...(next ? {cursor: next} : {})}), [prefs.sort, query]);

  const load = useCallback(async () => {
    const request = ++generation.current;
    setLoading(true); setError(null); setMoreError(null);
    try {
      const page = await host.request<NotePage>('backend.records.list', params());
      if (!alive.current || generation.current !== request) return;
      const items = normalizeNoteRows(page?.items);
      setRows(items);
      setCursor(typeof page?.nextCursor === 'string' ? page.nextCursor : null);
      if (initialNoteID && !appliedInitialPath.current) {
        appliedInitialPath.current = true;
        const local = items.find(row => row.record_id === initialNoteID);
        if (local) open(local);
        else void host.request<NoteRow>('backend.records.get', {collection: 'note', recordID: initialNoteID})
          .then(row => { const [safe] = normalizeNoteRows([row]); if (safe && alive.current) open(safe); }).catch(() => {});
      }
      if (!reportedDataReady.current) { reportedDataReady.current = true; void host.request('diagnostics.dataReady').catch(() => {}); }
    } catch (error) {
      if (alive.current && generation.current === request) setError(message(error, 'Notes could not load.'));
    } finally {
      if (alive.current && generation.current === request) setLoading(false);
    }
  }, [host, params, initialNoteID, open]);

  const loadMore = useCallback(async () => {
    if (!cursor || loading || loadingMore) return;
    const request = generation.current;
    setLoadingMore(true); setMoreError(null);
    try {
      const page = await host.request<NotePage>('backend.records.list', params(cursor));
      if (!alive.current || generation.current !== request) return;
      setRows(old => [...old, ...normalizeNoteRows(page?.items, old)]);
      setCursor(typeof page?.nextCursor === 'string' ? page.nextCursor : null);
    } catch (error) {
      if (alive.current && generation.current === request) setMoreError(message(error, 'More notes could not load.'));
    } finally {
      if (alive.current && generation.current === request) setLoadingMore(false);
    }
  }, [cursor, loading, loadingMore, host, params]);

  useEffect(() => { alive.current = true; return () => { alive.current = false; generation.current++; }; }, []);
  useEffect(() => { void load(); }, [load]);
  useEffect(() => { if (query !== prefs.query) setPrefs({...prefs, query}); }, [query]); // eslint-disable-line react-hooks/exhaustive-deps

  const visible = useMemo(() => orderForDisplay(rows.filter(row => !row.data.archived)), [rows]);
  const renderItem = useCallback(({item}: {item: NoteRow}) => <NoteCard row={item} theme={theme} open={open}/>, [theme, open]);
  const firstLoad = loading && rows.length === 0;
  const gap = theme.spacing.sm;
  const searching = query.length > 0;
  return <FlatList
    data={visible}
    keyExtractor={row => row.record_id}
    renderItem={renderItem}
    initialNumToRender={10}
    maxToRenderPerBatch={10}
    windowSize={9}
    // No removeClippedSubviews: it detaches off-screen rows from the accessibility tree,
    // so VoiceOver (and UI tests) can't reach notes below the fold. Pages are ≤50 rows.
    keyboardShouldPersistTaps="handled"
    keyboardDismissMode="on-drag"
    onEndReachedThreshold={0.4}
    onEndReached={() => { if (!moreError) void loadMore(); }}
    contentContainerStyle={{padding: theme.spacing.lg, paddingTop: theme.spacing.sm}}
    ItemSeparatorComponent={() => <View style={{height: gap}}/>}
    ListHeaderComponent={<View style={{gap: theme.spacing.md, marginBottom: theme.spacing.md}}>
      <ThemedText theme={theme} role="largeTitle" accessibilityRole="header">Your notes</ThemedText>
      <Toolbar theme={theme}>
        <View style={styles.flex}><ModuleButton theme={theme} title="New Note" onPress={create}/></View>
        <View style={styles.flex}><ModuleButton theme={theme} title="Reload notes" variant="secondary" disabled={loading} onPress={() => void load()}/></View>
      </Toolbar>
      <SearchField theme={theme} value={searchText} onChangeText={setSearchText} label="Search notes" placeholder="Search notes" testID="vault.search"/>
      <SegmentedControl theme={theme} label="Sort notes" options={SORTS} value={prefs.sort}
        onChange={sort => { setPrefs({...prefs, sort}); void host.request('haptics.selection').catch(() => {}); }}/>
      {loading && !firstLoad && <LoadingRow theme={theme} label="Loading notes"/>}
      {firstLoad && <View style={{gap: theme.spacing.sm}}><LoadingRow theme={theme} label="Loading notes"/><SkeletonRows theme={theme}/></View>}
      {error && <ModuleFallback theme={theme} title="Notes couldn’t load" message={error} action={{title: 'Try again', onPress: () => void load()}}/>}
      {!loading && !error && <ThemedText theme={theme} role="caption" secondary testID="vault.loaded">Notes loaded</ThemedText>}
    </View>}
    ListEmptyComponent={!loading && !error
      ? searching
        ? <ModuleFallback theme={theme} title="No matching notes" message={`Nothing matches “${query}”. Try other words or clear the search.`}
            action={{title: 'Clear search', onPress: () => setSearchText('')}} testID="vault.noResults"/>
        : <ModuleFallback theme={theme} title="Your Vault is empty" message="Notes you write stay private to your account. Create your first note."
            action={{title: 'Write a note', onPress: create}} testID="vault.empty"/>
      : undefined}
    ListFooterComponent={<View style={{gap: theme.spacing.sm, marginTop: theme.spacing.md}}>
      {loadingMore && <LoadingRow theme={theme} label="Loading more notes"/>}
      {moreError && <InlineNotice theme={theme} message={moreError} testID="vault.moreError" action={{title: 'Try again', onPress: () => void loadMore()}}/>}
      {cursor && !loadingMore && !moreError && <ModuleButton theme={theme} title="Load more notes" variant="secondary" disabled={loading} onPress={() => void loadMore()}/>}
      {!cursor && visible.length > 8 && <ThemedText theme={theme} role="caption" secondary style={styles.center}>
        {visible.length} notes</ThemedText>}
    </View>}
  />;
}

const INSERTS: {kind: InsertKind; label: string}[] = [
  {kind: 'heading', label: 'Heading'}, {kind: 'checklist', label: 'Checklist'}, {kind: 'bullet-list', label: 'List'},
  {kind: 'quote', label: 'Quote'}, {kind: 'divider', label: 'Divider'},
];

function Editor({record, host, theme, close}: {record?: NoteRow; host: Host; theme: ModuleTheme; close: () => void}) {
  const [current, setCurrent] = useState(record);
  const [title, setTitle] = useState(record?.data.title ?? '');
  const [text, setText] = useState(record?.data.plainTextProjection ?? '');
  // null = plain text mode (single field). Rich notes and notes with inserted blocks use segments.
  const [segments, setSegments] = useState<Segment[] | null>(record && !isPlainDocument(record.data.document)
    ? segmentsFromDocument(record.data.document) : null);
  const [pinned, setPinned] = useState(record?.data.pinned ?? false);
  const [busy, setBusy] = useState(Boolean(record));
  const [status, setStatus] = useState(record ? 'Loading note…' : 'New note');
  const [baseline, setBaseline] = useState(() => snapshot(record?.data.title ?? '', record?.data.plainTextProjection ?? '', segments, record?.data.pinned ?? false));
  const alive = useRef(true);

  function snapshot(t: string, x: string, s: Segment[] | null, p: boolean) { return JSON.stringify([t, s ? null : x, s, p]); }
  const dirty = snapshot(title, text, segments, pinned) !== baseline;

  function adopt(row: NoteRow) {
    const rich = !isPlainDocument(row.data.document);
    const nextSegments = rich ? segmentsFromDocument(row.data.document) : null;
    setCurrent(row); setTitle(row.data.title); setText(row.data.plainTextProjection); setSegments(nextSegments); setPinned(row.data.pinned);
    setBaseline(snapshot(row.data.title, row.data.plainTextProjection, nextSegments, row.data.pinned));
  }

  useEffect(() => {
    alive.current = true;
    if (record) void host.request<NoteRow>('backend.records.get', {collection: 'note', recordID: record.record_id}).then(raw => {
      const [row] = normalizeNoteRows([raw]);
      if (!alive.current) return;
      if (!row) { setStatus('This note could not be read. Close and try again.'); return; }
      adopt(row); setStatus('Ready to edit');
    }).catch(() => { if (alive.current) setStatus('Could not reload the note. Close and try again.'); })
      .finally(() => { if (alive.current) setBusy(false); });
    return () => { alive.current = false; };
  }, [host, record?.record_id]); // eslint-disable-line react-hooks/exhaustive-deps

  async function save() {
    if (busy) return; setBusy(true); setStatus('Saving…');
    try {
      const data = segments
        ? saveDocumentData(title, documentFromSegments(segments, current?.data.document), current?.data, {pinned})
        : saveData(title, text, current?.data, {pinned});
      const row = await host.request<NoteRow>(current ? 'backend.records.update' : 'backend.records.create', current
        ? {collection: 'note', recordID: current.record_id, expectedRevision: current.revision, data} : {collection: 'note', data});
      const [saved] = normalizeNoteRows([row]);
      if (alive.current) { if (saved) adopt(saved); setStatus('Saved'); }
      void host.request('haptics.selection').catch(() => {});
    } catch (error) {
      const text = message(error, 'The note could not be saved.');
      if (alive.current) setStatus(/revision|conflict/i.test(text) ? 'This note changed elsewhere. Go back to Notes and reopen it.' : text);
    } finally { if (alive.current) setBusy(false); }
  }
  async function remove() {
    if (!current || busy) return; setBusy(true);
    try { await host.request('backend.records.delete', {collection: 'note', recordID: current.record_id, expectedRevision: current.revision}); if (alive.current) close(); }
    catch (error) { if (alive.current) { setStatus(message(error, 'Could not move note to Trash.')); setBusy(false); } }
  }
  function back() {
    if (!dirty) { close(); return; }
    Alert.alert('Discard changes?', 'Your edits to this note haven’t been saved.', [
      {text: 'Keep Editing', style: 'cancel'}, {text: 'Discard', style: 'destructive', onPress: close}]);
  }
  function insert(kind: InsertKind) {
    const base = segments ?? segmentsFromText(text);
    setSegments([...base, newSegment(kind, base)]);
    void host.request('haptics.selection').catch(() => {});
  }
  const update = (index: number, next: Segment) => setSegments(old => old ? old.map((segment, i) => i === index ? next : segment) : old);
  const removeSegment = (index: number) => setSegments(old => old ? old.filter((_, i) => i !== index) : old);
  const input = {color: theme.colors.text, backgroundColor: theme.colors.surface, borderRadius: theme.radius.control,
    padding: theme.spacing.md, borderColor: theme.colors.border, fontSize: theme.type.body};
  return <KeyboardAvoidingView behavior="padding" style={styles.flex} keyboardVerticalOffset={0}>
    <ScrollView contentContainerStyle={{padding: theme.spacing.lg, gap: theme.spacing.md}} keyboardShouldPersistTaps="handled" keyboardDismissMode="interactive">
      <View style={[styles.rowBetween, {gap: theme.spacing.sm}]}>
        <ModuleButton theme={theme} title="Notes" variant="secondary" onPress={back} disabled={busy && status === 'Saving…'}/>
        <ThemedText theme={theme} role="caption" secondary>{dirty ? 'Unsaved changes' : current ? `Revision ${current.revision}` : ''}</ThemedText>
      </View>
      <TextInput accessibilityLabel="Note title" testID="vault.title" value={title} onChangeText={setTitle} editable={!busy}
        maxLength={240} placeholder="Note title" placeholderTextColor={theme.colors.textSecondary} allowFontScaling
        maxFontSizeMultiplier={theme.maxFontSizeMultiplier} style={[styles.input, input, {fontSize: theme.type.title, fontWeight: '600'}]}/>
      {segments
        ? <View style={{gap: theme.spacing.sm}} testID="vault.blocks">
            {segments.map((segment, index) => <SegmentEditor key={segment.id} theme={theme} segment={segment} disabled={busy}
              onChange={next => update(index, next)} onRemove={() => removeSegment(index)}/>)}
          </View>
        : <TextInput accessibilityLabel="Note content" testID="vault.content" value={text} onChangeText={setText} editable={!busy}
            multiline placeholder="Write a note" placeholderTextColor={theme.colors.textSecondary} allowFontScaling
            maxFontSizeMultiplier={theme.maxFontSizeMultiplier} style={[styles.input, styles.editor, input]}/>}
      <View style={{gap: theme.spacing.xs}}>
        <ThemedText theme={theme} role="caption" secondary>Add a block</ThemedText>
        {/* Wrapping toolbar (not a nested horizontal ScrollView, which ate the first tap to dismiss the keyboard). */}
        <Toolbar theme={theme}>
          {INSERTS.map(item => <ModuleButton key={item.kind} theme={theme} title={item.label} variant="secondary" disabled={busy}
            accessibilityHint={`Adds a ${item.label.toLowerCase()} at the end of the note`} onPress={() => insert(item.kind)}/>)}
        </Toolbar>
      </View>
      <ToggleRow theme={theme} label="Pin to top" value={pinned} onChange={setPinned} disabled={busy} testID="vault.pin"/>
      <ThemedText theme={theme} role="caption" secondary accessibilityRole="alert" testID="vault.saveStatus">{status}</ThemedText>
      <ModuleButton theme={theme} title="Save note" onPress={() => void save()} disabled={busy}/>
      {current && <ModuleButton theme={theme} title="Move to Trash" variant="destructive" disabled={busy}
        onPress={() => Alert.alert('Move note to Trash?', 'The note remains recoverable in Vault.', [
          {text: 'Cancel', style: 'cancel'}, {text: 'Move to Trash', style: 'destructive', onPress: () => void remove()}])}/>}
    </ScrollView>
  </KeyboardAvoidingView>;
}

/** One editable block. Non-editable blocks render read-only and can be removed. */
function SegmentEditor({theme, segment, disabled, onChange, onRemove}: {
  theme: ModuleTheme; segment: Segment; disabled: boolean; onChange: (next: Segment) => void; onRemove: () => void;
}) {
  const field = {color: theme.colors.text, fontSize: theme.type.body, paddingVertical: theme.spacing.xs, minHeight: theme.minimumTouchTarget};
  const frame = [styles.block, {backgroundColor: theme.colors.surface, borderRadius: theme.radius.control, borderColor: theme.colors.border,
    padding: theme.spacing.sm, gap: theme.spacing.xxs}];
  const label = segment.kind === 'text' ? ({paragraph: 'Paragraph', heading: 'Heading', quote: 'Quote', callout: 'Callout', code: 'Code'})[segment.role]
    : segment.kind === 'list' ? (segment.ordered ? 'Numbered list' : 'List') : segment.kind === 'checklist' ? 'Checklist'
    : segment.model.kind === 'divider' ? 'Divider' : 'Embedded content';
  const header = <View style={styles.rowBetween}>
    <ThemedText theme={theme} role="caption" secondary>{label}</ThemedText>
    <Pressable accessibilityRole="button" accessibilityLabel={`Remove ${label.toLowerCase()}`} disabled={disabled} onPress={onRemove}
      hitSlop={8} style={styles.iconButton}><ThemedText theme={theme} role="caption" secondary>✕</ThemedText></Pressable>
  </View>;
  switch (segment.kind) {
    case 'text': {
      const size = segment.role === 'heading' ? (segment.level === 1 ? theme.type.title : theme.type.headline) : theme.type.body;
      return <View style={[frame, segment.role === 'quote' && {borderLeftWidth: 3, borderLeftColor: theme.colors.accent}]}>{header}
        <TextInput accessibilityLabel={label} value={segment.text} editable={!disabled} multiline={segment.role !== 'heading'}
          onChangeText={text => onChange({...segment, text})} placeholder={label} placeholderTextColor={theme.colors.textSecondary}
          allowFontScaling maxFontSizeMultiplier={theme.maxFontSizeMultiplier}
          style={[field, {fontSize: size, fontWeight: segment.role === 'heading' ? '600' : '400',
            fontFamily: segment.role === 'code' ? 'Menlo' : undefined, fontStyle: segment.role === 'quote' ? 'italic' : 'normal'}]}/>
      </View>;
    }
    case 'list':
      return <View style={frame}>{header}
        <TextInput accessibilityLabel={`${label}, one item per line`} value={segment.items.join('\n')} editable={!disabled} multiline
          onChangeText={value => onChange({...segment, items: value.split('\n')})} placeholder="One item per line"
          placeholderTextColor={theme.colors.textSecondary} allowFontScaling maxFontSizeMultiplier={theme.maxFontSizeMultiplier} style={field}/>
      </View>;
    case 'checklist':
      return <View style={frame}>{header}
        {segment.items.map((item, index) => <View key={index} style={[styles.row, {gap: theme.spacing.xs}]}>
          <Pressable accessibilityRole="checkbox" accessibilityState={{checked: item.checked}} disabled={disabled}
            accessibilityLabel={item.text || `Item ${index + 1}`}
            onPress={() => onChange({...segment, items: segment.items.map((x, i) => i === index ? {...x, checked: !x.checked} : x)})}
            style={styles.iconButton} hitSlop={6}>
            <ThemedText theme={theme} style={{color: item.checked ? theme.colors.accent : theme.colors.textSecondary}}>{item.checked ? '☑' : '☐'}</ThemedText>
          </Pressable>
          <TextInput accessibilityLabel={`Checklist item ${index + 1}`} value={item.text} editable={!disabled}
            onChangeText={text => onChange({...segment, items: segment.items.map((x, i) => i === index ? {...x, text} : x)})}
            onSubmitEditing={() => onChange({...segment, items: [...segment.items, {text: '', checked: false}]})}
            placeholder="To do" placeholderTextColor={theme.colors.textSecondary} returnKeyType="next" blurOnSubmit={false}
            allowFontScaling maxFontSizeMultiplier={theme.maxFontSizeMultiplier}
            style={[field, {flex: 1, textDecorationLine: item.checked ? 'line-through' : 'none'}]}/>
        </View>)}
        <Pressable accessibilityRole="button" accessibilityLabel="Add checklist item" disabled={disabled}
          onPress={() => onChange({...segment, items: [...segment.items, {text: '', checked: false}]})} style={{minHeight: theme.minimumTouchTarget, justifyContent: 'center'}}>
          <ThemedText theme={theme} style={{color: theme.colors.accent}}>＋ Add item</ThemedText>
        </Pressable>
      </View>;
    case 'static':
      return <View style={frame}>{header}<DocumentBlocks theme={theme} blocks={[segment.model]}/></View>;
  }
}

const styles = StyleSheet.create({
  root: {flex: 1},
  meta: {flexDirection: 'row', flexWrap: 'wrap'},
  flex: {flex: 1},
  row: {flexDirection: 'row', alignItems: 'center'},
  rowBetween: {flexDirection: 'row', alignItems: 'center', justifyContent: 'space-between'},
  center: {textAlign: 'center'},
  block: {borderWidth: StyleSheet.hairlineWidth},
  iconButton: {minWidth: 36, minHeight: 36, alignItems: 'center', justifyContent: 'center'},
  input: {minHeight: 48, borderWidth: StyleSheet.hairlineWidth},
  editor: {minHeight: 180, textAlignVertical: 'top'},
});
