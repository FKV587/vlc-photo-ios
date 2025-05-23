/*****************************************************************************
 * VLCDropboxTableViewController.m
 * VLC for iOS
 *****************************************************************************
 * Copyright (c) 2013-2015 VideoLAN. All rights reserved.
 * $Id$
 *
 * Authors: Felix Paul Kühne <fkuehne # videolan.org>
 *          Gleb Pinigin <gpinigin # gmail.com>
 *          Carola Nitz <nitz.carola # googlemail.com>
 *          Fabio Ritrovato <sephiroth87 # videolan.org>
 *          Tamas Timar <ttimar.vlc # gmail.com>
 *          Eshan Singh <eeeshan789 # gmail.com>
 * Refer to the COPYING file of the official project for license.
 *****************************************************************************/

#import "VLCDropboxTableViewController.h"
#import "VLCDropboxController.h"
#import "VLCCloudStorageTableViewCell.h"
#import "VLCAppDelegate.h"
#import "VLC-Swift.h"

@interface VLCDropboxTableViewController () <VLCCloudStorageTableViewCell, VLCCloudStorageDelegate>
{
    VLCDropboxController *_dropboxController;
    DBFILESMetadata *_selectedFile;
    DBFILESFolderMetadata *_folder;
    NSArray *_mediaList;
}

@end

@implementation VLCDropboxTableViewController

- (instancetype)initWithPath:(NSString *)path
{
    self = [super init];
    if (self) {
        self.currentPath = path;
    }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    _dropboxController = [VLCDropboxController sharedInstance];
    self.controller = _dropboxController;
    self.controller.delegate = self;

    self.navigationItem.titleView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"dropbox-white"]];

    [self.cloudStorageLogo setImage:[UIImage imageNamed:@"dropbox-white.png"]];

    [self.cloudStorageLogo sizeToFit];
    self.cloudStorageLogo.center = self.view.center;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    self.controller = [VLCDropboxController sharedInstance];
    self.controller.delegate = self;

    [self requestInformationForCurrentPath];   
    
    if (self.currentPath != nil)
        self.title = self.currentPath.lastPathComponent;

    [self updateViewAfterSessionChange];
    [self.tableView reloadData];
}

#pragma mark - interface interaction

- (BOOL)shouldAutorotate
{
    UIInterfaceOrientation toInterfaceOrientation = [[UIApplication sharedApplication] statusBarOrientation];
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone && toInterfaceOrientation == UIInterfaceOrientationPortraitUpsideDown)
        return NO;
    return YES;
}

#pragma mark - Table view data source

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"DropboxCell";

    VLCCloudStorageTableViewCell *cell = (VLCCloudStorageTableViewCell *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (cell == nil)
        cell = [VLCCloudStorageTableViewCell cellWithReuseIdentifier:CellIdentifier];

    NSUInteger index = indexPath.row;
    if (_mediaList) {
        if (index < _mediaList.count) {
            cell.dropboxFile = _mediaList[index];
            cell.delegate = self;
        }
    }

    return cell;
}

- (void)mediaListUpdated
{
    _mediaList = [self.controller.currentListFiles copy];

    [super mediaListUpdated];
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    _selectedFile = _mediaList[indexPath.row];
    if (![_selectedFile isKindOfClass:[DBFILESFolderMetadata class]])
        [_dropboxController streamFile:_selectedFile currentNavigationController:self.navigationController];
    else {
        /* dive into subdirectory */
        NSString *futurePath = [self.currentPath stringByAppendingFormat:@"/%@", _selectedFile.name];
        self.currentPath = futurePath;
        [self requestInformationForCurrentPath];
    }
    _selectedFile = nil;

    [self.tableView deselectRowAtIndexPath:indexPath animated:NO];
}

#pragma mark - login dialog

- (IBAction)loginAction:(id)sender
{
    if (!_dropboxController.isAuthorized) {
        self.authorizationInProgress = YES;

        [DBClientsManager authorizeFromControllerV2:[UIApplication sharedApplication]
                                         controller:self
                              loadingStatusDelegate:nil
                                            openURL:^(NSURL * _Nonnull url) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];

        } scopeRequest:nil];
    } else
        [_dropboxController logout];
}

- (void)sessionWasUpdated:(NSNotification *)aNotification
{
    self.authorizationInProgress = YES;
    [self updateViewAfterSessionChange];

    [_dropboxController shareCredentials];
}

#pragma mark - VLCCloudStorageTableViewCell delegation

- (void)triggerDownloadForCell:(VLCCloudStorageTableViewCell *)cell
{
    if ([_mediaList[[self.tableView indexPathForCell:cell].row] isKindOfClass:[DBFILESFolderMetadata class]]) {
        _folder = _mediaList[[self.tableView indexPathForCell:cell].row];
    } else {
        _selectedFile = _mediaList[[self.tableView indexPathForCell:cell].row];
    }
    
    /* selected item is a proper file, ask the user if s/he wants to download it */
    NSArray<VLCAlertButton *> *buttonsAction = @[
        [[VLCAlertButton alloc] initWithTitle:NSLocalizedString(@"BUTTON_CANCEL", nil)
                                       style:UIAlertActionStyleCancel
                                      action:^(UIAlertAction *action) {
            self->_selectedFile = nil;
        }],
        [[VLCAlertButton alloc] initWithTitle:NSLocalizedString(@"BUTTON_DOWNLOAD", nil)
                                      action:^(UIAlertAction *action) {
            if (self->_folder == NULL) {
                [self->_dropboxController downloadFileToDocumentFolder:self->_selectedFile];
                self->_selectedFile = nil;
            } else {
                [self->_dropboxController downloadFolderFiles:self->_folder];
                self->_folder = nil;
            }
        }]
    ];
    
    [VLCAlertViewController alertViewManagerWithTitle:NSLocalizedString(@"DROPBOX_DOWNLOAD", nil)
                                         errorMessage:[NSString stringWithFormat:NSLocalizedString(@"DROPBOX_DL_LONG", nil), _selectedFile.name, [[UIDevice currentDevice] model]]
                                       viewController:self
                                        buttonsAction:buttonsAction];
}

- (void)triggerFavoriteForCell:(VLCCloudStorageTableViewCell *)cell
{
    
    NSIndexPath *indexPath = [self.tableView indexPathForCell:cell];
    VLCFavoriteService *service = [VLCAppCoordinator sharedInstance].favoriteService;
    _selectedFile = _mediaList[indexPath.row];

    VLCFavorite *fav = [[VLCFavorite alloc] init];
    fav.userVisibleName = _selectedFile.name;
    fav.url = [NSURL URLWithString:[NSString stringWithFormat:@"file://DropBox/%@", _selectedFile.pathLower]];

    if (cell.isFavourite) {
        [service addFavorite:fav];
    } else {
        [service removeFavorite:fav];
    }
    
}


@end
