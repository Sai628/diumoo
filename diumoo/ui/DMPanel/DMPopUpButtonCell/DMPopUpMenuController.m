//
//  DMPopUpMenuController.m
//  diumoo
//
//  Created by Shanzi on 12-6-16.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "DMPopUpMenuController.h"
#import "DMDoubanAuthHelper.h"

#define UPDATE_URL @"http://diumoo-notification.herokuapp.com/fmchannel/"
#define DJ_EXPLORER_URL @"http://douban.fm/j/explore/"

#define kDMCollectChannel @"collect_channel"
#define kDMUncollectChannel @"uncollect_channel"

#import "CJSONDeserializer.h"
#import "NSDictionary+UrlEncoding.h"

@implementation DMPopUpMenuController

@synthesize delegate;
@synthesize publicMenu,suggestMenu,currentChannelMenuItem;
@synthesize currentChannelID,specialMode;


-(void) awakeFromNib
{
    

    currentChannelID = [[[NSUserDefaults standardUserDefaults]
                         valueForKey:@"channel"]integerValue];
    
    if (currentChannelID == 0 || currentChannelID == -3) {
        self.currentChannelMenuItem = [mainMenu itemWithTag:currentChannelID];
    }
}

-(void)popUpMenu:(id)sender
{
    NSView* view = sender;
    NSRect rect = [view convertRect:view.bounds toView:nil];
    NSPoint point = NSMakePoint(rect.origin.x + rect.size.width, 
                                rect.origin.y + rect.size.height
                                );
    
    NSEvent* event = [NSEvent mouseEventWithType:NSLeftMouseUp
                                        location:point
                                   modifierFlags:0
                                       timestamp:0
                                    windowNumber:view.window.windowNumber 
                                         context:nil
                                     eventNumber:0
                                      clickCount:1 
                                        pressure:1];
    
    
    NSMenu* menuToPopup = nil;
    
    if ([sender tag] == -1) {
        menuToPopup = shareMenu;
    }
    else if (self.specialMode) {
        menuToPopup = exitSpecialMenu;
    }
    else if ([sender tag]) {
        menuToPopup = mainMenu;
    }
    else {
        
        if (currentChannelID > 1000000) {
            menuToPopup = moreChannelMenu;
        }
        else if(currentChannelID > 0) {
            menuToPopup = publicMenu;
        }
    }

    [NSMenu popUpContextMenu:menuToPopup withEvent:event forView:sender];
}

-(void) updateChannelList
{
    NSString* filepath = [[NSBundle mainBundle] pathForResource:@"channels" ofType:@"plist"];
    
    NSDictionary* channelDict = [NSDictionary dictionaryWithContentsOfFile:filepath];
    
    NSArray* public_list = nil;
    NSArray* suggest_list = nil;
    
    if (channelDict != nil) {
        double timestamp = [[channelDict valueForKey:@"timestamp"] doubleValue];
        if(([NSDate timeIntervalSinceReferenceDate] - timestamp) > 3600 * 24 * 3){
            DMLog(@"获取新的列表");
            // -------------------------获取新的列表--------------------------
            NSURL* updateUrl = [NSURL URLWithString:UPDATE_URL];
            NSURLRequest* urlrequest = [NSURLRequest requestWithURL:updateUrl
                                                        cachePolicy:NSURLCacheStorageAllowed
                                                    timeoutInterval:3.0];
            NSURLResponse* response = NULL;
            NSError* error = NULL;
            NSData* data = [NSURLConnection sendSynchronousRequest:urlrequest
                                                 returningResponse:&response
                                                             error:&error];
            
            
            if(error==NULL){
                NSDictionary* dict = [[CJSONDeserializer deserializer] deserializeAsDictionary:data error:&error];
                
                if(error == NULL){
                    public_list = [dict valueForKey:@"public"];
                    suggest_list = [dict valueForKey:@"suggest"];
                    
                    if ([public_list count] && [suggest_list count]) {
                        
                        NSNumber* timestamp = @([NSDate timeIntervalSinceReferenceDate]);
                        
                        NSDictionary* writedic = @{@"public": public_list,
                                                  @"suggest": suggest_list,
                                                  @"timestamp": timestamp};
                        DMLog(@"写入电台列表");
                        [writedic writeToFile:filepath atomically:YES];
                        [self updateMenuItemsWithPublicList:public_list andSuggestList:suggest_list];
                        
                        return;
                    }
                }
            }
            //----------------------------------------------------------------------
            
        }
    }
    
    
    public_list = [channelDict valueForKey:@"public"];
    suggest_list = [channelDict valueForKey:@"suggest"];
    [self updateMenuItemsWithPublicList:public_list andSuggestList:suggest_list];
}

-(void) updateMenuItemsWithPublicList:(NSArray*) publiclist andSuggestList:(NSArray*) suggestlist
{

    NSInteger maxPublicChannelId = 0;
    if (publiclist) {
        self.publicMenu = [self buildMenuWithChannelListArray:publiclist maxChannelID:&maxPublicChannelId];
        [[mainMenu itemWithTag:1] setSubmenu:publicMenu];
    }
    if (suggestlist)
    {
        self.suggestMenu = [self buildMenuWithChannelListArray:suggestlist maxChannelID:NULL];
        [[moreChannelMenu itemWithTag:-12] setSubmenu:suggestMenu];
        [[mainMenu itemWithTag:1000000]setSubmenu:moreChannelMenu];
    }
    
    
    NSArray* oldRecentDJ = [moreChannelMenu itemArray];
    for (NSMenuItem* item in oldRecentDJ) {
        if ([item tag]>0 && item.state != NSOnState) {
            [moreChannelMenu removeItem:item];
        }
    }
    
    NSArray* promotions = [DMDoubanAuthHelper sharedHelper].promotion_chls;
    NSArray* recents = [DMDoubanAuthHelper sharedHelper].recent_chls;
    
    if ([promotions count]>0) {
        NSMenuItem* pemptyItem = [moreChannelMenu itemWithTag:-14];
        NSInteger index = [moreChannelMenu indexOfItem:pemptyItem];
        [pemptyItem setHidden:YES];
        
        for (NSDictionary* channel in promotions) {
            NSLog(@"channel %@",channel);
            NSInteger tag = [[channel valueForKey:@"id"] integerValue];
            NSString* title = [channel valueForKey:@"name"];
            NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title 
                                                          action:@selector(changeChannelAction:)
                                                   keyEquivalent:@""] ;
            [item setTarget:self];
            [item setIndentationLevel:1];
            [item setTag:tag];
            [moreChannelMenu insertItem:item atIndex:index];
            if (tag == currentChannelID) {
                self.currentChannelMenuItem = item;
            }
        }
    }
    else{
        [[moreChannelMenu itemWithTag:-14] setHidden:NO];
    }
    
    if ([recents count]>0) {
        
        NSInteger displayedCount = 0;
        for (NSDictionary* channel in promotions) {
            
            NSInteger tag = [[channel valueForKey:@"id"] integerValue];
            if (tag < maxPublicChannelId) continue;
            
            NSString* title = [channel valueForKey:@"name"];
            NSMenuItem* item = [[NSMenuItem alloc] initWithTitle:title
                                                          action:@selector(changeChannelAction:)
                                                   keyEquivalent:@""] ;
            [item setTarget:self];
            [item setIndentationLevel:1];
            [item setTag:tag];
            [moreChannelMenu addItem:item];
            displayedCount += 1;
            if (tag == currentChannelID) {
                self.currentChannelMenuItem = item;
            }
        }
        
        if (displayedCount) [[moreChannelMenu itemWithTag:-13] setHidden:YES];
    }
    else{
        [[moreChannelMenu itemWithTag:-13] setHidden:NO];
    }
}

-(NSMenu*) buildMenuWithChannelListArray:(NSArray*)array maxChannelID:(NSInteger*) maxid
{
    NSMenu* menu = [[NSMenu alloc] init];
    for (NSDictionary* dic in array) {
        if([dic valueForKey:@"cate"])
        {
            if ([menu numberOfItems] > 0) {
                [menu addItem:[NSMenuItem separatorItem]];
            }
            
            NSMenuItem* cateitem = [[NSMenuItem alloc]
                                    initWithTitle:[dic valueForKey:@"cate"] 
                                    action:nil
                                    keyEquivalent:@""] ;
            [menu addItem:cateitem];
            
            NSArray* channelsArray = [dic valueForKey:@"channels"];
            for (NSDictionary* channel in channelsArray) {
                NSMenuItem* item = [[NSMenuItem alloc] 
                                    initWithTitle:[channel valueForKey:@"name"]
                                    action:@selector(changeChannelAction:)
                                    keyEquivalent:@""];
                
                NSInteger tag = [[channel valueForKey:@"channel_id"] integerValue];
                [item setTag:tag];
                [item setIndentationLevel:1];
                [item setTarget:self];
                [menu addItem:item];
                if (maxid!=NULL && (*maxid) < tag) {
                    (*maxid) = tag;
                }
                if (tag == currentChannelID) {
                    self.currentChannelMenuItem = item;
                }
            }
        }
    }
    return menu;
}


-(void) changeChannelAction:(id)sender
{
    [[self delegate] performSelector:@selector(channelChangeActionWithSender:) 
                          withObject:sender];
}

-(void) updateChannelMenuWithSender:(id)sender
{
    //DMLog(@"ismain: %d,%@",[NSThread isMainThread],[NSThread currentThread]);
    NSMenuItem* citem = currentChannelMenuItem;
    NSMenuItem* newItem = nil;
    
    while (citem != nil) {
        [citem setState:NSOffState];
        citem = [citem parentItem];
    }
    
    
    NSInteger tag = [sender tag];
    
    
    if (tag <1) {
        newItem = sender;
        [longMainButton setTitle:[sender title]];
        [longMainButton setHidden:NO];
        
    }
    else if( [publicMenu itemWithTag:tag] != nil){
        newItem = sender;
        NSMenuItem* publicMenuItem = [mainMenu itemWithTag:1];
        [mainButton setTitle:publicMenuItem.title];
        [subButton setTitle:[newItem title]];
        [longMainButton setHidden:YES];
    }
    else{
        NSMenuItem* moreChannelMenuItem = [mainMenu itemWithTag:1000000];
        [mainButton setTitle:moreChannelMenuItem.title];
        [subButton setTitle:[sender title]];
        
        // -------------------------- 处理兆赫的菜单和记录 --------------------------
        
        newItem = [moreChannelMenu itemWithTag:tag]; //先检查当前的兆赫是不是已经在最近播放的列表里了
        
        
        if(newItem == nil){
            // 当前的dj兆赫还没被加入到最近播放列表，现在加入它
            newItem = [sender copy];
            
            // 先获取到当前dj菜单下所有item，检查item的数量是否超过了要求，超过了的话，就删掉一些
            NSArray* menuarray = [moreChannelMenu itemArray];
            if ([menuarray count]>20) {
                NSMenuItem* itemToRemove = [menuarray lastObject];
                if ([itemToRemove tag] > 1000000) {
                    [moreChannelMenu removeItem:itemToRemove];
                }
            }
            
            
            // 把“空”字样那个菜单项隐藏掉
            NSMenuItem* itemToHide = [moreChannelMenu itemWithTag:-13];
            [itemToHide setHidden:YES];
            
            // 计算将新item插入的index
            NSInteger indexToInsert = [moreChannelMenu indexOfItem:itemToHide] +1;
            [newItem setIndentationLevel:1];
            [moreChannelMenu insertItem:newItem atIndex:indexToInsert];
        }
        [longMainButton setHidden:YES];
    }
    
    [newItem setState:NSOnState];
    NSMenuItem* pitem = [newItem parentItem];
    while (pitem!=nil) {
        [pitem setState:NSMixedState];
        pitem = [pitem parentItem];
    }
    
    
    
    self.currentChannelID = tag;
    self.currentChannelMenuItem = newItem;
    
    
    [[NSUserDefaults standardUserDefaults] setValue:@(currentChannelID) forKey:@"channel"]; // 把当前的兆赫记录到偏好设置里
    
}

-(void) enterSpecialPlayingModeWithTitle:(NSString *)title artist:(NSString*)artist andTypeString:(NSString*) type
{
    self.specialMode = YES;
    
    NSString* typeTitle = [NSString stringWithFormat:@"%@:%@",type,title];
    NSString* fullTitle = [@"名称 : " stringByAppendingString:title];
    
    [longMainButton setTitle:typeTitle];
    [longMainButton setHidden:NO];
    
    NSString* exitTitle = [NSString stringWithFormat:@"返回“%@”兆赫",[currentChannelMenuItem title]];
    NSString* fulltype = [@"类型 : " stringByAppendingString:type];
    
    [[exitSpecialMenu itemWithTag:0] setTitle:exitTitle];
    [[exitSpecialMenu itemWithTag:1] setTitle:fullTitle];
    [[exitSpecialMenu itemWithTag:2] setTitle:artist];
    [[exitSpecialMenu itemWithTag:3] setTitle:fulltype];
    
}

-(void) exitSepecialPlayingMode
{
    if (self.currentChannelID < 1) {
        [longMainButton setTitle:[currentChannelMenuItem title]];
    }
    else {
        [longMainButton setHidden:YES];
    }
    
    self.specialMode = NO;
}

-(void) setPrivateChannelEnabled:(BOOL)enable
{

    NSMenuItem* itemHeartChannel = [mainMenu itemWithTag:-3];
    NSMenuItem* itemPrivateChannel = [mainMenu itemWithTag:0];
    
    if (enable == NO) {

        if (itemHeartChannel.state != NSOffState || itemPrivateChannel.state != NSOffState) {
            [self changeChannelAction:[publicMenu itemWithTag:1]];
        }
        itemPrivateChannel.action = nil;
        itemHeartChannel.action = nil;
    }
    else {
        [itemHeartChannel setAction:@selector(changeChannelAction:)];
        [itemPrivateChannel setAction:@selector(changeChannelAction:)];
    }
    
}


-(void) unlockChannelMenuButton
{
    [longMainButton setEnabled:YES];
    [mainButton setEnabled:YES];
    [subButton setEnabled:YES];
}

-(void) invokeChannelWith:(NSInteger)cid andTitle:(NSString *)title andPlay:(BOOL)playImmediately
{
    NSMenuItem* item =nil;
    if (cid == 0) {
        item = [mainMenu itemWithTag:0];
    }
    else{
        item = [publicMenu itemWithTag:cid];
        if (item == nil) {
            item = [moreChannelMenu itemWithTag:cid];
            if (item == nil) {
                item = [[NSMenuItem alloc] initWithTitle:title action:@selector(changeChannelAction:)
                                           keyEquivalent:@""];
                item.tag = cid;
                
                [item setTarget:self];
                
            }
        }
    }
    
    
    if (playImmediately) {
        [self changeChannelAction:item];
    }
    else{
        [self updateChannelMenuWithSender:item];
        [[NSUserDefaults standardUserDefaults] setValue:@(cid) forKey:@"channel"];
    }
    
}

@end
