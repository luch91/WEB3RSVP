//SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

contract WEB3RSVP{
// Define Events
    event NewEventCreated(
        bytes32 eventID,
        address creatorAddress,
        uint256 eventTimestamp,
        uint256 maxCapacity,
        uint256 deposit,
        string eventDataCID
    );

    event NewRSVP(bytes32 eventID, address attendeeAddress);

    event ConfirmedAttendee(bytes32 eventID, address attendeeAddress);

    event DepositsPaidOut(bytes32 eventID);


    struct CreateEvent {
        bytes32 eventId;
        string eventDataCID;
        address eventOwner;
        uint256 eventTimeStamp;
        uint256 deposit;
        uint256 maxCapacity;
        address[] confirmedRSVPs;
        address[] claimedRSVPs;
        bool paidOut;
    }

    mapping(bytes32 => CreateEvent) public idToEvent;

    function createNewEvent(
        uint256 eventTimeStamp, 
        uint256 deposit, 
        uint256 maxCapacity, 
        string calldata eventDataCID
    ) external{
        //generate an eventID based on other things passed in to generate a hash
        bytes32 eventId = keccak256(
            abi.encodePacked(
                msg.sender,
                address(this),
                eventTimeStamp,
                deposit,
                maxCapacity
            )
        );

        address[] memory confirmedRSVPs;
        address[] memory claimedRSVPs;


        // this creates a new CreateEvent struct and adds it to the idToEvent mapping
        idToEvent[eventId] = CreateEvent(
            eventId,
            eventDataCID,
            msg.sender,
            eventTimeStamp,
            deposit,
            maxCapacity,
            confirmedRSVPs,
            claimedRSVPs,
            false

        ); 
        
        emit NewEventCreated(
        eventId,
        msg.sender,
        eventTimeStamp,
        maxCapacity,
        deposit,
        eventDataCID
        );
    }


//*** RSVP TO EVENT

    function createNewRSVP(bytes32 eventId) external payable {
        // look up event from our mapping
        CreateEvent storage myEvent = idToEvent[eventId];

        //transfer deposit to our contract / require that they send in enough ETH to cover the deposit requirement of this specific event
        require(msg.value == myEvent.deposit, "NOT ENOUGH ETH");

        // require that the event hasn't already happened (<eventTimeStamp)
        require(block.timestamp <= myEvent.eventTimeStamp, "ALREADY HAPPENED, APPLY NEXT MONTH");

        // ensure event is under max capacity
        require(
            myEvent.confirmedRSVPs.length < myEvent.maxCapacity,
            "Sorry, this event has reached capacity"
        );

        // require that msg.sender isn't already in myEvent.confirmedRSVPs : hasn't already RSVP'd
        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            require(myEvent.confirmedRSVPs[i] != msg.sender, "ALREADY CONFIRMED" );

        }

        myEvent.confirmedRSVPs.push(payable(msg.sender));

        emit NewRSVP(eventId, msg.sender);
    }

///**** CHECK IN ATTENDEES

    function confirmAttendee(bytes32 eventId, address attendee ) public {
        //look up event from our struct using the eventId
        CreateEvent storage myEvent = idToEvent[eventId];


        //require that msg.sender is the owner
        require(msg.sender == myEvent.eventOwner, "NOT AUTHORIZED");

        //require that attendee trying to check in actually RSVP'd
        address rsvpConfirm;

        for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++) {
            if(myEvent.confirmedRSVPs[i] == attendee) {
                rsvpConfirm = myEvent.confirmedRSVPs[i];

            }
        }
        
        require(rsvpConfirm == attendee, "NO RSVP TO CONFIRM");

        //require that attendee is not already in the claimedRSVPs list: to make sure they haven't already checked in
        for(uint8 i = 0; i < myEvent.claimedRSVPs.length; i++) {
            require(myEvent.claimedRSVPs[i] != attendee, "ALREADY CLAIMED");

        }

        //require that deposits are not already claimed by the event owner
        require(myEvent.paidOut == false, "ALREADY PAID OUT");

        //add the attendee to the claimedRSVPs lists
        myEvent.claimedRSVPs.push(attendee);

        //sending eth back to the staker https://solidity-by-example.org/sending-ether
        (bool sent,) = attendee.call{value:myEvent.deposit}("");

        if (!sent) {
            myEvent.claimedRSVPs.pop();
        }

        require(sent, "Failed to send Ether");

        emit ConfirmedAttendee(eventId, attendee);    

    }

 //**** CONFIRMING THE WHOLE GROUP: to confirm all of the attendees at once instead of one at a time. A function to confirm every person that has RSVPS to a specific event:

    function confirmAllAttendees(bytes32 eventId) external {

        // look up event from our struct with the eventId
        CreateEvent memory myEvent =idToEvent[eventId];

        //make sure you require that msg.sender is the owner of the event
       require(msg.sender == myEvent.eventOwner, "NOT AUTHORIZED" );

       //confirm each attendee in the rsvp array
       for (uint8 i = 0; i < myEvent.confirmedRSVPs.length; i++){
            confirmAttendee(eventId, myEvent.confirmedRSVPs[i]);
       }   

    }
//SEND UNCLAIMED DEPOSITS TO EVENT ORGANIZER: this function below will withdraw deposits of people who didn't show up
//to the event organizer:

    function withdrawUnclaimedDeposits(bytes32 eventId) external {
        //look up event
        CreateEvent memory myEvent = idToEvent[eventId];

        // check that the paidOut boolean still equals false: the money hasn't already been paid out
        require(!myEvent.paidOut, "ALREADY PAID");

        //Check if it's been 7 days past myEvent.event.Timestamp
        require(
            block.timestamp >= (myEvent.eventTimeStamp + 7 days),
            "TOO EARLY");

        // only the event owner can withdraw
        require(msg.sender == myEvent.eventOwner, "MUST BE EVENT OWNER" );


        // calculate how many people didn't claim by comparing
        uint256 unclaimed = myEvent.confirmedRSVPs.length - myEvent.claimedRSVPs.length;
      
        uint256 payout = unclaimed * myEvent.deposit;

        //mark as paid before sending to avoid reentrancy attack
        myEvent.paidOut = true;

        //send the payouy to the owner
        (bool sent, ) = msg.sender.call{value: payout}("");

        // if this fails
        if (!sent) {
            myEvent.paidOut == false;
        
        }

        require(sent, "Failed to send Ether");

        emit DepositsPaidOut(eventId);
    
    }  

}
