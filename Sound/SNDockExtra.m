/*
 * Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
 * SPDX-License-Identifier: BSD-2-Clause
 */

#import "SNDockExtra.h"
#import <GNUstepBase/GNUstep.h>

/* How long the Dock has to answer before the app takes it that no Dock
   is running. */
#define SNDockAnswerSeconds 2.0

@interface SNDockExtra (Private)
- (void)dockChanged:(NSNotification *)note;
- (void)noAnswer:(NSTimer *)timer;
- (void)tell;
@end

@implementation SNDockExtra

/* Read from the file rather than through NSUserDefaults, which in a
   long-running app may not see the Dock's change to a domain outside
   its own search list. */
+ (NSArray *)hiddenExtras
{
  NSString *path = [GSDefaultsRootForUser (NSUserName ())
                     stringByAppendingPathComponent:
                       [SNDockDomain stringByAppendingPathExtension:@"plist"]];
  id hidden = [[NSDictionary dictionaryWithContentsOfFile:path]
                objectForKey:SNDockExtrasHiddenKey];

  return [hidden isKindOfClass:[NSArray class]] ? hidden : [NSArray array];
}

- (id)initWithIdentifier:(NSString *)anIdentifier
              bundleName:(NSString *)aBundleName
{
  if ((self = [super init]) == nil)
    return nil;
  ASSIGNCOPY (identifier, anIdentifier);
  ASSIGNCOPY (bundleName, aBundleName);
  [[NSDistributedNotificationCenter defaultCenter]
      addObserver:self
         selector:@selector (dockChanged:)
             name:SNDockExtrasChangedNotification
           object:nil];
  return self;
}

- (void)dealloc
{
  [self invalidate];
  RELEASE (identifier);
  RELEASE (bundleName);
  [super dealloc];
}

- (void)invalidate
{
  [[NSDistributedNotificationCenter defaultCenter] removeObserver:self];
  [answerTimer invalidate];
  DESTROY (answerTimer);
  target = nil;
}

- (void)setTarget:(id)aTarget action:(SEL)anAction
{
  target = aTarget;
  action = anAction;
}

- (BOOL)isInstalled
{
  NSFileManager *fm = [NSFileManager defaultManager];
  NSString *name = [bundleName stringByAppendingPathExtension:@"dockextra"];
  NSMutableArray *dirs = [NSMutableArray arrayWithObjects:
      [NSHomeDirectory () stringByAppendingPathComponent:@"Library"],
      @"/Local/Library", @"/System/Library", nil];
  NSUInteger i;

  /* Where the Dock looks (apps-dock DockExtrasController), and GNUstep's
     Library folders where they are elsewhere. */
  [dirs addObjectsFromArray:
          NSSearchPathForDirectoriesInDomains (NSLibraryDirectory,
                                               NSAllDomainsMask, YES)];
  for (i = 0; i < [dirs count]; i++)
    {
      NSString *path = [[[dirs objectAtIndex:i]
                          stringByAppendingPathComponent:@"DockExtras"]
                         stringByAppendingPathComponent:name];
      if ([fm fileExistsAtPath:path])
        return YES;
    }
  return NO;
}

- (BOOL)isShown
{
  if (pending)
    return !pendingHidden;
  return ![[SNDockExtra hiddenExtras] containsObject:identifier];
}

- (void)setShown:(BOOL)shown
{
  pending = YES;
  pendingHidden = !shown;
  [answerTimer invalidate];
  ASSIGN (answerTimer,
          [NSTimer scheduledTimerWithTimeInterval:SNDockAnswerSeconds
                                           target:self
                                         selector:@selector (noAnswer:)
                                         userInfo:nil
                                          repeats:NO]);
  NS_DURING
    [[NSDistributedNotificationCenter defaultCenter]
        postNotificationName:SNDockSetExtraHiddenNotification
                      object:nil
                    userInfo:[NSDictionary dictionaryWithObjectsAndKeys:
                                identifier, @"identifier",
                                [NSNumber numberWithBool:!shown], @"hidden",
                                nil]
          deliverImmediately:YES];
  NS_HANDLER
    NSLog (@"Can't ask the Dock to %@ %@: %@", shown ? @"show" : @"hide",
           identifier, [localException reason]);
  NS_ENDHANDLER
}

@end

@implementation SNDockExtra (Private)

/* The Dock changed its extras (answering us, or anyone). */
- (void)dockChanged:(NSNotification *)note
{
  pending = NO;
  [answerTimer invalidate];
  DESTROY (answerTimer);
  [self tell];
}

/* No Dock running: its defaults are ours to write. */
- (void)noAnswer:(NSTimer *)timer
{
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSMutableDictionary *domain;
  NSMutableArray *hidden;

  DESTROY (answerTimer);
  if (!pending)
    return;
  pending = NO;
  [defaults synchronize];
  domain = [NSMutableDictionary dictionaryWithDictionary:
             [defaults persistentDomainForName:SNDockDomain]];
  hidden = [NSMutableArray arrayWithArray:[SNDockExtra hiddenExtras]];
  [hidden removeObject:identifier];
  if (pendingHidden)
    [hidden addObject:identifier];
  [domain setObject:hidden forKey:SNDockExtrasHiddenKey];
  [defaults setPersistentDomain:domain forName:SNDockDomain];
  [defaults synchronize];
  [self tell];
}

- (void)tell
{
  if (target != nil && action != NULL)
    [target performSelector:action withObject:self];
}

@end
