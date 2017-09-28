// Copyright (c) 2005 - 2015 Settlers Freaks (sf-team at siedler25.org)
//
// This file is part of Return To The Roots.
//
// Return To The Roots is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 2 of the License, or
// (at your option) any later version.
//
// Return To The Roots is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with Return To The Roots. If not, see <http://www.gnu.org/licenses/>.
#ifndef dskLOBBY_H_INCLUDED
#define dskLOBBY_H_INCLUDED

#pragma once

#include "desktops/dskMenuBase.h"

#include "ClientInterface.h"
#include "liblobby/LobbyInterface.h"

class iwLobbyServerInfo;
class iwDirectIPCreate;
class LobbyServerList;
class LobbyPlayerList;

class dskLobby : public dskMenuBase, public ClientInterface, public LobbyInterface
{
private:
    const LobbyServerList* serverlist;
    const LobbyPlayerList* playerlist;
    iwLobbyServerInfo* serverInfoWnd;
    iwDirectIPCreate* createServerWnd;

public:
    dskLobby();

    void UpdatePlayerList(bool first = false);
    void UpdateServerList(bool first = false);

    void LC_Connected() override;

    void LC_Status_ConnectionLost() override;
    void LC_Status_IncompleteMessage() override;
    void LC_Status_Error(const std::string& error) override;

    void LC_Chat(const std::string& player, const std::string& text) override;

protected:
    void Msg_Timer(const unsigned ctrl_id) override;
    void Msg_PaintBefore() override;
    void Msg_MsgBoxResult(const unsigned msgbox_id, const MsgboxResult mbr) override;
    void Msg_ButtonClick(const unsigned ctrl_id) override;
    void Msg_EditEnter(const unsigned ctrl_id) override;
    void Msg_TableRightButton(const unsigned ctrl_id, const int selection) override;
    void Msg_TableChooseItem(const unsigned ctrl_id, const unsigned selection) override;

    /**
     * Connectes to the currently selected game and returns true on success
     */
    bool ConnectToSelectedGame();
};

#endif // dskLOBBY_H_INCLUDED
