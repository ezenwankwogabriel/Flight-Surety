
import DOM from './dom';
import Contract from './contract';
import './flightsurety.css';


(async() => {

    let result = null;

    let contract = new Contract('localhost', () => {

        // Read transaction
        contract.isOperational((error, result) => {
            console.log(error,result);
            display('Operational Status', 'Check if contract is operational', [ { label: 'Operational Status', error: error, value: result} ]);
        });
    

        // User-submitted transaction
        DOM.elid('submit-oracle').addEventListener('click', () => {
            let flight = DOM.elid('select-flight').value;
            // Write transaction
            contract.fetchFlightStatus(flight, (error, result) => {
                let list = [ { label: 'Fetch Flight Status', error: error, value: result.status } ];
                if (result.funds) 
                    list.push({ label: 'Refunded Amount', error: error, value: result.funds + 'ether' })
                
                    display('Oracles', 'Trigger oracles', list);
            });
        })

        DOM.elid('pay-insurance').addEventListener('click', () => {
            let insuranceAmount = DOM.elid('insurance-amount').value;
            if (insuranceAmount > 1) return alert('Selected insurance fee should be less than one');
            let selecedOption = DOM.elid('select-flight').value;
            if (!selecedOption) throw new Error('No option selected')
            // Write transaction
            contract.payInsurance(selecedOption, insuranceAmount, (error, result) => {
                console.log(error, result)
                display('Buy Insurance', 'Pay insurance for flight', [ { label: 'Pay insurance', error: error, value: result[0] === true ? `Successfully paid ${result[1]} ether` : '' } ])
            })
        })
    
    });

})();


function display(title, description, results) {
    let displayDiv = DOM.elid("display-wrapper");
    let section = DOM.section();
    section.appendChild(DOM.h2(title));
    section.appendChild(DOM.h5(description));
    results.map((result) => {
        let row = section.appendChild(DOM.div({className:'row'}));
        row.appendChild(DOM.div({className: 'col-sm-4 field'}, result.label));
        row.appendChild(DOM.div({className: 'col-sm-8 field-value'}, result.error ? String(result.error) : String(result.value)));
        section.appendChild(row);
    })
    displayDiv.append(section);

}







