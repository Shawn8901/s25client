// Copyright (c) 2005 - 2017 Settlers Freaks (sf-team at siedler25.org)
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

#include "rttrDefines.h" // IWYU pragma: keep
#include "ctrlChat.h"
#include "CollisionDetection.h"
#include "FileChecksum.h"
#include "ctrlScrollBar.h"
#include "driver/MouseCoords.h"
#include "ogl/glArchivItem_Font.h"
#include "libutil/Log.h"

/// Breite der Scrollbar
static const unsigned short SCROLLBAR_WIDTH = 20;

/**
 *  Konstruktor von @p ctrlChat.
 *
 *  @param[in] parent Elternfenster
 *  @param[in] id     ID des Steuerelements
 *  @param[in] x      X-Position
 *  @param[in] y      Y-Position
 *  @param[in] width  Breite des Controls
 *  @param[in] height Höhe des Controls
 *  @param[in] tc     Hintergrundtextur
 *  @param[in] font   Schriftart
 */
ctrlChat::ctrlChat(Window* parent, unsigned id, const DrawPoint& pos, const Extent& size, TextureColor tc, glArchivItem_Font* font)
    : Window(parent, id, pos, size), tc(tc), font(font), time_color(0xFFFFFFFF)
{
    // Zeilen pro Seite festlegen errechnen
    page_size = (size.y - 4) / (font->getHeight() + 2);

    // Scrollbalken hinzufügen
    AddScrollBar(0, DrawPoint(size.x - SCROLLBAR_WIDTH, 0), Extent(SCROLLBAR_WIDTH, size.y), SCROLLBAR_WIDTH, tc, page_size);

    // Breite der Klammern <> um die Spielernamen berechnen
    bracket1_size = font->getWidth("<");
    bracket2_size = font->getWidth("> ");
}

ctrlChat::~ctrlChat() {}

/**
 *  Größe ändern
 */
void ctrlChat::Resize(const Extent& newSize)
{
    const bool x_changed = (GetSize().x != newSize.x && !chat_lines.empty());
    Window::Resize(newSize);

    ctrlScrollBar* scroll = GetCtrl<ctrlScrollBar>(0);
    scroll->SetPos(DrawPoint(newSize.x - SCROLLBAR_WIDTH, 0));
    scroll->Resize(Extent(SCROLLBAR_WIDTH, newSize.y));

    // Remember some things
    const bool was_on_bottom = (scroll->GetScrollPos() + page_size == chat_lines.size());
    unsigned short position = 0;
    // Remember the entry on top
    for(unsigned short i = 1; i <= scroll->GetScrollPos(); ++i)
        if(!chat_lines[i].secondary)
            ++position;

    // Rewrap
    if(x_changed)
    {
        chat_lines.clear();
        for(unsigned short i = 0; i < raw_chat_lines.size(); ++i)
            WrapLine(i);
    }

    // Zeilen pro Seite festlegen errechnen
    page_size = (newSize.y - 4) / (font->getHeight() + 2);

    scroll->SetPageSize(page_size);

    // If we are were on the last line, keep
    if(was_on_bottom)
    {
        scroll->SetScrollPos(((chat_lines.size() > page_size) ? chat_lines.size() - page_size : 0));
    } else if(x_changed)
    {
        unsigned short i;
        for(i = 0; position > 0; ++i)
            if(!chat_lines[i].secondary)
                --position;
        scroll->SetScrollPos(i);
    }

    // Don't display empty lines at the end if there are this is
    // not necessary because of a lack of lines in total
    if(chat_lines.size() < page_size)
        scroll->SetScrollPos(0);
    else if(scroll->GetScrollPos() + page_size > chat_lines.size())
        scroll->SetScrollPos(chat_lines.size() - page_size);
}

/**
 *  Zeichnet das Chat-Control.
 */
void ctrlChat::Draw_()
{
    // Box malen
    Draw3D(Rect(GetDrawPos(), GetSize()), tc, false);

    Window::Draw_();

    // Wieviele Linien anzeigen?
    unsigned show_lines = (page_size > unsigned(chat_lines.size()) ? unsigned(chat_lines.size()) : page_size);

    // Listeneinträge zeichnen
    // Add margin
    DrawPoint textPos = GetDrawPos() + DrawPoint(2, 2);
    unsigned pos = GetCtrl<ctrlScrollBar>(0)->GetScrollPos();
    for(unsigned i = 0; i < show_lines; ++i)
    {
        // eine zweite oder n-nte Zeile?
        if(chat_lines[i + pos].secondary)
            font->Draw(textPos, chat_lines[i + pos].msg, 0, chat_lines[i + pos].msg_color);
        else
        {
            DrawPoint curTextPos = textPos;

            // Zeit, Spieler und danach Textnachricht
            if(!chat_lines[i + pos].time_string.empty())
            {
                font->Draw(curTextPos, chat_lines[i + pos].time_string, 0, time_color);
                curTextPos.x += font->getWidth(chat_lines[i + pos].time_string);
            }

            if(!chat_lines[i + pos].player.empty())
            {
                // Klammer 1 (<)
                font->Draw(curTextPos, "<", 0, chat_lines[i + pos].player_color);
                curTextPos.x += bracket1_size;
                // Spielername
                font->Draw(curTextPos, chat_lines[i + pos].player, 0, chat_lines[i + pos].player_color);
                curTextPos.x += font->getWidth(chat_lines[i + pos].player);
                // Klammer 2 (>)
                font->Draw(curTextPos, "> ", 0, chat_lines[i + pos].player_color);
                curTextPos.x += bracket2_size;
            }

            font->Draw(curTextPos, chat_lines[i + pos].msg, 0, chat_lines[i + pos].msg_color);
        }
        textPos.y += font->getHeight() + 2;
    }
}

void ctrlChat::WrapLine(unsigned short i)
{
    ChatLine line = raw_chat_lines[i];

    // Breite von Zeitstring und Spielername berechnen (falls vorhanden)
    unsigned short prefix_width = (line.time_string.length() ? font->getWidth(line.time_string) : 0)
                                  + (line.player.length() ? (bracket1_size + bracket2_size + font->getWidth(line.player)) : 0);

    // Reicht die Breite des Textfeldes noch nichtmal dafür aus?
    if(prefix_width > GetSize().x - 2 - SCROLLBAR_WIDTH)
    {
        // dann können wir das gleich vergessen
        return;
    }

    // Zeilen ggf. wrappen, falls der Platz nich reicht und die Zeilenanfanänge in wi speichern
    glArchivItem_Font::WrapInfo wi =
      font->GetWrapInfo(line.msg, GetSize().x - prefix_width - 2 - SCROLLBAR_WIDTH, GetSize().x - 2 - SCROLLBAR_WIDTH);

    // Message-Strings erzeugen aus den WrapInfo
    std::vector<std::string> strings = wi.CreateSingleStrings(line.msg);

    // Zeilen hinzufügen
    for(unsigned i = 0; i < strings.size(); ++i)
    {
        ChatLine wrap_line;
        // Nur bei den ersten Zeilen müssen ja Zeit und Spielername mit angegeben werden
        wrap_line.secondary = i != 0;
        if(!wrap_line.secondary)
        {
            wrap_line.time_string = line.time_string;
            wrap_line.player = line.player;
            wrap_line.player_color = line.player_color;
        }

        wrap_line.msg = strings[i];
        wrap_line.msg_color = line.msg_color;

        chat_lines.push_back(wrap_line);
    }
}

void ctrlChat::AddMessage(const std::string& time_string, const std::string& player, const unsigned player_color, const std::string& msg,
                          const unsigned msg_color)
{
    ChatLine line;

    line.time_string = time_string;
    line.player = player;
    line.player_color = player_color;
    line.msg = msg;
    line.msg_color = msg_color;
    raw_chat_lines.push_back(line);

    const size_t oldlength = chat_lines.size();

    // Loggen
    LOG.write("%s <") % time_string;
    LOG.writeColored(player, player_color);
    LOG.write(">: ");
    LOG.writeColored(msg, msg_color);
    LOG.write("\n");

    // Umbrechen
    WrapLine(raw_chat_lines.size() - 1);

    // Scrollbar Bescheid sagen
    ctrlScrollBar* scrollbar = GetCtrl<ctrlScrollBar>(0);
    scrollbar->SetRange(unsigned(chat_lines.size()));

    // Waren wir am Ende? Dann mit runterscrollen
    if(scrollbar->GetScrollPos() + page_size == oldlength)
        scrollbar->SetScrollPos(chat_lines.size() - page_size);
}

bool ctrlChat::Msg_MouseMove(const MouseCoords& mc)
{
    return RelayMouseMessage(&Window::Msg_MouseMove, mc);
}

bool ctrlChat::Msg_LeftDown(const MouseCoords& mc)
{
    return RelayMouseMessage(&Window::Msg_LeftDown, mc);
}

bool ctrlChat::Msg_LeftUp(const MouseCoords& mc)
{
    return RelayMouseMessage(&Window::Msg_LeftUp, mc);
}

bool ctrlChat::Msg_WheelUp(const MouseCoords& mc)
{
    if(IsPointInRect(mc.GetPos(), Rect(GetDrawPos() + DrawPoint(2, 2), GetSize() - Extent(2, 4))))
    {
        ctrlScrollBar* scrollbar = GetCtrl<ctrlScrollBar>(0);
        scrollbar->Scroll(-3);
        return true;
    } else
        return false;
}

bool ctrlChat::Msg_WheelDown(const MouseCoords& mc)
{
    if(IsPointInRect(mc.GetPos(), Rect(GetDrawPos() + DrawPoint(2, 2), GetSize() - Extent(2, 4))))
    {
        ctrlScrollBar* scrollbar = GetCtrl<ctrlScrollBar>(0);
        scrollbar->Scroll(+3);
        return true;
    } else
        return false;
}

unsigned ctrlChat::CalcUniqueColor(const std::string& name)
{
    unsigned checksum = CalcChecksumOfBuffer(name.c_str(), name.length()) * name.length();
    unsigned color = checksum | (checksum << 12) | 0xff000000;
    return color;
}
