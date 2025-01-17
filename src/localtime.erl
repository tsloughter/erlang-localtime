%% Copyright (C) 07/01/2010 Dmitry S. Melnikov (dmitryme@gmail.com)
%%
%% This program is free software; you can redistribute it and/or
%% modify it under the terms of the GNU General Public License
%% as published by the Free Software Foundation; either version 2
%% of the License, or (at your option) any later version.
%%
%% This program is distributed in the hope that it will be useful,
%% but WITHOUT ANY WARRANTY; without even the implied warranty of
%% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
%% GNU General Public License for more details.
%%
%% You should have received a copy of the GNU General Public License
%% along with this program; if not, write to the Free Software
%% Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
-module(localtime).

-author("Dmitry Melnikov <dmitryme@gmail.com>").

-include("tz_database.hrl").
-include("tz_index.hrl").

-export(
  [
     utc_to_local_seconds/2
     ,utc_to_local/2
     ,local_to_utc/2
     ,local_to_local/3
     ,tz_name/2
     ,tz_shift/2
     ,tz_shift/3
  ]).

-spec utc_to_local_seconds(integer(), list()) -> integer() | {error, atom()}.
utc_to_local_seconds(UtcSeconds, Timezone) when is_integer(UtcSeconds) ->
   case lists:keyfind(get_timezone(Timezone), 1, ?tz_database) of
      false ->
         {error, unknown_tz};
      {_Tz, _, _, Shift, _DstShift, undef, _DstStartTime, undef, _DstEndTime} ->
         adjust_datetime(UtcSeconds, Shift);
      TzRule = {_, _, _, Shift, DstShift, _, _, _, _} ->
         LocalDateTime = adjust_datetime(UtcSeconds, Shift),
         case localtime_dst:check(calendar:gregorian_seconds_to_datetime(LocalDateTime), TzRule) of
            Res when (Res == is_in_dst) or (Res == time_not_exists) ->
               adjust_datetime(LocalDateTime, DstShift);
            is_not_in_dst ->
               LocalDateTime;
            ambiguous_time ->
               RecheckIt = adjust_datetime(LocalDateTime, DstShift),
               case localtime_dst:check(RecheckIt, TzRule) of
                  ambiguous_time ->
                     RecheckIt;
                  _ ->
                     LocalDateTime
               end
         end
   end.

% utc_to_local(UtcDateTime, Timezone) -> LocalDateTime | {error, ErrDescr}
%  UtcDateTime = DateTime()
%  Timezone = String()
%  LocalDateTime = DateTime()
%  ErrDescr = atom(), unknown_tz
utc_to_local(UtcDateTime, Timezone) ->
   case lists:keyfind(get_timezone(Timezone), 1, ?tz_database) of
      false ->
         {error, unknown_tz};
      {_Tz, _, _, Shift, _DstShift, undef, _DstStartTime, undef, _DstEndTime} ->
         adjust_datetime(UtcDateTime, Shift);
      TzRule = {_, _, _, Shift, DstShift, _, _, _, _} ->
         LocalDateTime = adjust_datetime(UtcDateTime, Shift),
         case localtime_dst:check(LocalDateTime, TzRule) of
            Res when (Res == is_in_dst) or (Res == time_not_exists) ->
               adjust_datetime(LocalDateTime, DstShift);
            is_not_in_dst ->
               LocalDateTime;
            ambiguous_time ->
               RecheckIt = adjust_datetime(LocalDateTime, DstShift),
               case localtime_dst:check(RecheckIt, TzRule) of
                  ambiguous_time ->
                     RecheckIt;
                  _ ->
                     LocalDateTime
               end
         end
   end.

% local_to_utc(LocalDateTime, Timezone) -> UtcDateTime | tim_not_exists | {error, ErrDescr}
%  LocalDateTime = DateTime()
%  Timezone = String()
%  UtcDateTime = DateTime()
%  ErrDescr = atom(), unknown_tz
local_to_utc(LocalDateTime, Timezone) ->
   case lists:keyfind(get_timezone(Timezone), 1, ?tz_database) of
      false ->
         {error, unknown_tz};
      {_Tz, _, _, Shift, _DstShift, undef, _DstStartTime, undef, _DstEndTime} ->
         adjust_datetime(LocalDateTime, invert_shift(Shift));
      TzRule = {_, _, _, Shift, DstShift, _, _, _, _} ->
         UtcDateTime = adjust_datetime(LocalDateTime, invert_shift(Shift)),
         case localtime_dst:check(LocalDateTime, TzRule) of
            is_in_dst ->
               adjust_datetime(UtcDateTime, invert_shift(DstShift));
            Res when (Res == is_not_in_dst) or (Res == ambiguous_time) ->
               UtcDateTime;
            time_not_exists ->
               time_not_exists
         end
   end.

% local_to_local(LocalDateTime, TimezoneFrom, TimezoneTo) -> LocalDateTime | tim_not_exists | {error, ErrDescr}
%  LocalDateTime = DateTime()
%  TimezoneFrom = String()
%  TimezoneTo = String()
%  ErrDescr = atom(), unknown_tz
local_to_local(LocalDateTime, TimezoneFrom, TimezoneTo) ->
   case local_to_utc(LocalDateTime, TimezoneFrom) of
      Date = {{_,_,_},{_,_,_}} ->
         utc_to_local(Date, TimezoneTo);
      Res ->
         Res
   end.

% tz_name(DateTime(), Timezone) -> {Abbr, Name} | {{StdAbbr, StdName}, {DstAbbr, DstName}} | unable_to_detect | {error, ErrDesc}
%  Timezone = String()
%  Abbr = String()
%  Name = String()
%  StdAbbr = String()
%  StdName = String()
%  DstAbbr = String()
%  DstName = String()
%  ErrDesc = atom(), unknown_tz
tz_name(_UtcDateTime, "UTC") ->
   {"UTC", "UTC"};
tz_name(LocalDateTime, Timezone) ->
   case lists:keyfind(get_timezone(Timezone), 1, ?tz_database) of
      false ->
         {error, unknown_tz};
      {_Tz, StdName, undef, _Shift, _DstShift, undef, _DstStartTime, undef, _DstEndTime} ->
         StdName;
      TzRule = {_, StdName, DstName, _Shift, _DstShift, _, _, _, _} ->
         case localtime_dst:check(LocalDateTime, TzRule) of
            is_in_dst ->
               DstName;
            is_not_in_dst ->
               StdName;
            ambiguous_time ->
               {StdName, DstName};
            time_not_exists ->
               unable_to_detect
         end
   end.

% tz_shift(LocalDateTime, Timezone) ->  Shift | {Shift, DstSift} | unable_to_detect | {error, ErrDesc}
%  returns time shift from GMT
%  LocalDateTime = DateTime()
%  Timezone = String()
%  Shift = DstShift = {Sign, Hours, Minutes}
%  Sign = term(), '+', '-'
%  Hours = Minutes = Integer(),
%  {Shift, DstShift} - returns, when shift is ambiguous
%  ErrDesc = atom(), unknown_tz
tz_shift(_UtcDateTime, "UTC") ->
   0;
tz_shift(LocalDateTime, Timezone) ->
   case lists:keyfind(get_timezone(Timezone), 1, ?tz_database) of
      false ->
         {error, unknown_tz};
      {_Tz, _StdName, undef, Shift, _DstShift, undef, _DstStartTime, undef, _DstEndTime} ->
         fmt_min(Shift);
      TzRule = {_, _StdName, _DstName, Shift, DstShift, _, _, _, _} ->
         case localtime_dst:check(LocalDateTime, TzRule) of
            is_in_dst ->
               fmt_min(Shift + DstShift);
            is_not_in_dst ->
               fmt_min(Shift);
            ambiguous_time ->
               {fmt_min(Shift), fmt_min(Shift + DstShift)};
            time_not_exists ->
               unable_to_detect
         end
   end.

% the same as tz_shift/2, but calculates time difference between two local timezones
tz_shift(LocalDateTime, TimezoneFrom, TimezoneTo) ->
   F = fun() ->
      FromShift = fmt_shift(tz_shift(LocalDateTime, TimezoneFrom)),
      DateTimeTo = localtime:local_to_local(LocalDateTime, TimezoneFrom, TimezoneTo),
      ToShift = fmt_shift(tz_shift(DateTimeTo, TimezoneTo)),
      fmt_min(ToShift-FromShift)
   end,
   try F()
   catch
      _:Err ->
         Err
   end.

% =======================================================================
% privates
% =======================================================================

adjust_datetime(Seconds, Minutes) when is_integer(Seconds) ->
    Seconds + Minutes * 60;

adjust_datetime(DateTime, Minutes) ->
   Seconds = calendar:datetime_to_gregorian_seconds(DateTime) + Minutes * 60,
   calendar:gregorian_seconds_to_datetime(Seconds).

invert_shift(Minutes) ->
   -Minutes.

fmt_min(Shift) when Shift < 0 ->
   {'-', abs(Shift) div 60, abs(Shift) rem 60};
fmt_min(Shift) ->
   {'+', Shift div 60, Shift rem 60}.

fmt_shift({'+', H, M}) ->
   H * 60 + M;
fmt_shift({'-', H, M}) ->
   -(H * 60 + M);
fmt_shift(Any) ->
   throw(Any).

get_timezone(TimeZone) ->
   case dict:find(TimeZone, ?tz_index)  of
      error ->
         TimeZone;
      {ok, [TZName | _]} ->
            TZName
   end.
