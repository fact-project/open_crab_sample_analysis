from fact.io import read_data, to_h5py
import pandas as pd
import h5py
import click


@click.command()
@click.argument('inputfile')
@click.argument('outputfile')
def main(inputfile, outputfile):

    df = read_data(
        inputfile,
        key='events',
        columns=[
            'night',
            'run_id',
            'event_num',
            'gamma_prediction',
            'gamma_energy_prediction',
            'ra_prediction',
            'dec_prediction',
            'unix_time_utc',
            'theta_deg',
            'theta_deg_off_1',
            'theta_deg_off_2',
            'theta_deg_off_3',
            'theta_deg_off_4',
            'theta_deg_off_5',
        ],
    )

    df['timestamp'] = pd.to_datetime(
        df['unix_time_utc_0'] * 1e6 + df['unix_time_utc_1'],
        unit='us',
    )
    df.drop(['unix_time_utc_0', 'unix_time_utc_1'], axis=1, inplace=True)

    to_h5py(outputfile, df, key='events', mode='w')

    with h5py.File(outputfile, 'r+') as f:

        with h5py.File(inputfile, 'r') as infile:
            infile.copy('runs', f)

        f['events']['night'].attrs['comment'] = 'int representing the night of observation as YYYYMMDD.\n Day change is at 12:00 '
        f['events']['run_id'].attrs['comment'] = 'Integer ID of the run, resets each night'
        f['events']['event_num'].attrs['comment'] = 'Integer ID of the event, resets each run'
        f['events']['gamma_prediction'].attrs['comment'] = 'Score of the RandomForestClassifier for the particle classification.\n1 means most likely a gamma, 0 most likely background'
        f['events']['gamma_energy_prediction'].attrs['comment'] = 'Energy prediction of a RandomForestRegressor in GeV'
        f['events']['ra_prediction'].attrs['comment'] = 'Right Ascension prediction of gamma-ray origin in hourangle.\nThe disp method was used with two RandomForests, a Regressor for |disp| and a Classifier for sgn(disp)'
        f['events']['dec_prediction'].attrs['comment'] = 'Declination prediction of gamma-ray origin in degree.\nThe disp method was used with two RandomForests, a Regressor for |disp| and a Classifier for sgn(disp)'
        f['events']['timestamp'].attrs['comment'] = 'UTC timestamp of the Event as ISO String. Accurate only to ms level.'

        f['events']['theta_deg'].attrs['comment'] = 'Angular distance of reconstructed source position to true position of the Crab nebula'
        f['events']['theta_deg'].attrs['unit'] = 'deg'
        for i in range(1, 6):
            col = 'theta_deg_off_{}'.format(i)
            f['events'][col].attrs['comment'] = 'Angular distance of reconstructed source position to off position {}'.format(i)
            f['events'][col].attrs['unit'] = 'deg'

        f['events']['night'].attrs['unit'] = ''
        f['events']['run_id'].attrs['unit'] = ''
        f['events']['event_num'].attrs['unit'] = ''
        f['events']['gamma_prediction'].attrs['unit'] = ''
        f['events']['gamma_energy_prediction'].attrs['unit'] = 'GeV'
        f['events']['ra_prediction'].attrs['unit'] = 'ha'
        f['events']['dec_prediction'].attrs['unit'] = 'deg'
        f['events']['timestamp'].attrs['unit'] = ''


if __name__ == '__main__':
    main()
