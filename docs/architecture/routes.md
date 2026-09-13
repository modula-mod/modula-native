# Canonical native routes

N2 authority: `AppRoute` is the in-process route model. `RouteParser` converts paths and supported links to typed values; `RouteSerializer` emits canonical paths. Feature views must not pass route strings through SwiftUI. Strings exist only at deep-link, restoration, serialization, test, and module-request boundaries.

## Global map

```text
/
/auth/{login,register,verify,forgot-password,reset-password,welcome}
/home/{following,for-you,modules}
/discover/{trending,people,topics,posts,modules}
/search[/{people,posts,modules,topics}]?q=
/post/:postId[/{comments,likes,reactions,shares,edit}]
/compose/{post,photo,video,link,poll,carousel,audio,movie}
/activity/{all,mentions,requests}
/notifications[/:notificationId]
/profile/:userId/{overview,posts,modules,followers,following,connections,links,edit}
/me[/{overview,posts,modules,followers,following,connections,links,edit}]
/product-hub/{featured,modules,tools,functions,plugins,connections,widgets,installed,updates,coming-soon,developer}
/product-hub/category/:categoryId
/product-hub/publisher/:publisherId
/product-hub/search?q=
/product-hub/module/:moduleId[/{overview,whats-new,permissions,privacy,information,screenshots,version-history,compatibility,publisher,support,configure}]
/module/:moduleId[/<module-local-path>]
/settings
/settings/account/{personal-information,username,email,password,sessions,delete-account}
/settings/appearance/{theme,dark-style,accent,typography,app-icon,density,motion,haptics,contrast-transparency,icon-style,interface-shape,module-branding,preview}
/settings/appearance/typography/{font-family,text-size}
/settings/notifications/{push,social,modules,quiet-hours}
/settings/privacy-security/{privacy,security,glass-privacy,blocked,app-lock,biometrics}
/settings/modules/{installed,updates,auto-updates,permissions}
/settings/modules/:moduleId/{general,permissions,data,updates,diagnostics,about}
/settings/data-storage/{storage,cache,downloads,backup,export}
/settings/accessibility/{text,contrast,motion}
/settings/features/{enabled,experimental}
/settings/updates/channel/{stable,unstable}
/settings/updates/version-lock
/settings/developer/{runtime,modules,network,feature-flags,environment,components,diagnostics}
/settings/about/{version,licenses,privacy,terms}
/messages/{new,:conversationId}
/teams/{create,:teamId}
/teams/:teamId/{overview,members,roles,modules,settings}
/developer/{components,appearance,modules,runtime,bridge,diagnostics}
```

Defaults serialize as `/home/following`, `/activity/all`, `/profile/:userId/overview`, and `/product-hub/featured`. `/me` is a semantic current-account route and does not manufacture an account identifier.

`/product-hub/module/:moduleId` is native product information. `/module/:moduleId` creates the native `ModuleHost`. Anything after the module ID is opaque module-local state; for example `/module/digital.modula.vault-notes/note/123` passes `/note/123` into Vault. Swift never interprets it as an app route.

The parser accepts path strings, `modula://…`, and `https://modula.digital/…`. Other origins, traversal, encoded separators, control characters, unknown routes, and oversized input fail closed. Universal-link entitlements remain infrastructure work.

Retired appearance paths `/settings/appearance/surface` and `/settings/appearance/color-family` are invalid. Material is a design-system decision, not a user-facing surface preference.
