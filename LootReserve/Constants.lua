LootReserve = LootReserve or { };
LootReserve.Constants =
{
    ReserveResult =
    {
        OK = 0,
        NoSession = 1,
        NotMember = 2,
        AlreadyReserved = 3,
        NoReservesLeft = 4,
    },
    CancelReserveResult =
    {
        OK = 0,
        NoSession = 1,
        NotMember = 2,
        NotReserved = 3,
    },
};